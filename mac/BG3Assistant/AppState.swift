import AppKit
import Foundation

enum ChatRole: String {
    case user
    case assistant
}

struct ChatLine: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    var sources: [ChatSource] = []
    var imageData: Data?
    /// Local failure notes (e.g. backend offline) render as assistant bubbles
    /// but are never sent back to the model as conversation history.
    var isError = false
}

@MainActor
final class AppState: ObservableObject {
    private static let storedSettings = RunStore().loadSettings()

    @Published var gameDetected = false
    @Published var backendHealthy = false
    @Published var backendAIAvailable = false
    @Published var showOverlay = true { didSet { syncOverlay() } }
    @Published var forceOverlay = false { didSet { syncOverlay() } }
    @Published var overlayExpanded = false {
        didSet {
            if overlayExpanded { maybeShowHint(.plannerMap) }
            syncOverlay()
        }
    }
    @Published var moreContextExpanded = false { didSet { if overlayExpanded { syncOverlay() } } }
    @Published var plannerTab: PlannerTab = .current { didSet { if overlayExpanded { syncOverlay() } } }
    @Published var overlayDensity = OverlayDensity(
        rawValue: storedSettings.overlayDensity
    ) ?? .focus {
        didSet {
            persistSettings()
            syncOverlay()
        }
    }
    // The active one-time coach mark; at most one per session (see
    // maybeShowHint in AppState+Overlay).
    @Published var activeHint: HintID? { didSet { syncOverlay() } }
    var hintShownThisSession = false
    // The intake wizard renders in place of the planner/peek card while
    // non-nil; only finishing or skipping records it as seen.
    @Published var onboardingStep: OnboardingStep? = (storedSettings.onboardingSeenVersion ?? 0) >= OnboardingStep.version
        ? nil : .welcome { didSet { syncOverlay() } }
    @Published var onboardingMode: OnboardingMode = .fresh
    @Published var onboardingCatchUpCheckpointId: String?
    // Login-item consent, applied only when the wizard finishes (never on
    // skip). Defaults on: the disclosure sits next to the toggle.
    @Published var onboardingEnableLoginItem = true
    var onboardingSeenVersion: Int? = storedSettings.onboardingSeenVersion
    var onboardingCompleted: Bool = storedSettings.onboardingCompleted ?? false
    var seenHints: Set<String> = Set(storedSettings.seenHints ?? [])
    // Route step to scroll to and expand when the route tab opens (set by the
    // peek card's Talk shortcut so the current conversation is front and center).
    // Backed by the run so cross-process adoption can never desync it.
    var focusedWalkthroughStepId: String? {
        get { run.focusedWalkthroughStepId }
        set { run.focusedWalkthroughStepId = newValue }
    }
    @Published var route: [RouteCheckpoint] = []
    @Published var walkthrough: [WalkthroughStep] = []
    @Published var timedEvents: [TimedEvent] = []
    @Published var builds: [BuildSummary] = []
    @Published var itemCatalog: [ItemSummary] = []
    @Published var acts: [ActGuideSummary] = []
    @Published var run: HonorRun
    @Published var readiness: ReadinessResponse?
    @Published var statusMessage = "Loading Act 1 guide…"
    @Published var errorMessage: String?
    @Published var chatDraft = ""
    @Published var chatLines: [ChatLine] = []
    @Published var chatScreenshot: ScreenshotResult?
    @Published var isPreparingChatScreenshot = false
    @Published var isSendingChat = false
    @Published var chatScope: ChatScope = .current
    @Published var skipNoteDraft = ""
    @Published var pendingDisposition: CheckpointDisposition?
    @Published var confirmationMessage: String?
    @Published var pendingRosterStatusChange: PendingRosterStatusChange?
    @Published var partyUndoState: PartyUndoState?
    @Published var combatCardPinned = false
    @Published var snoozedUntil: Date?
    @Published var availableGuideVersion = ""
    @Published var newRunConfirmation = false
    @Published var savedRuns: [SavedRunSummary] = []
    @Published var runNameDraft = ""
    @Published var newRunNameDraft = ""
    @Published var screenCaptureVerifiedThisLaunch = false
    @Published var showScreenRecordingPermissionPrompt = false
    @Published var loadoutURLDraft = ""
    @Published var isImportingLoadout = false
    @Published var loadoutImportStatus: String?
    @Published var loadoutImportJSON: String?
    @Published private(set) var loadedGuideAct: Int?
    @Published private(set) var loadedRouteAvailable = false

    private let detector = BG3Detector()
    let backendClient = BackendClient()
    private let backendProcess = BackendProcessManager()
    let captureService = ScreenCaptureService()
    let runStore = RunStore()
    let overlayController = OverlayPanelController()
    private var isStarting = false
    private var pollTask: Task<Void, Never>?
    private var loadingGuideAct: Int?
    private var guideLoadGeneration = 0
    var chatGeneration = 0
    @Published private(set) var gameWindowFrame: CGRect?

    // Capture permission has three intentionally separate signals: raw TCC
    // preflight, a successful pixel capture, and whether this launch already
    // invoked the registration request. Never infer one from another.
    var captureAuthorized = false
    var permissionRequestAttemptedThisLaunch = false
    var permissionProbeAfterSettings = false
    var captureAuthorizationRefreshInFlight = false
    var lastCaptureProbe = Date.distantPast
    private var activationObserver: Any?
    private var plannerRequestObserver: Any?
    var sharedRunToken: RunStore.ChangeToken?

    init() {
        var loaded = runStore.load()
        loaded.migrateLegacyPartySlots()
        if loaded.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            loaded.name = "Honor Run 1"
        }
        if loaded.createdAt == nil { loaded.createdAt = .now }
        run = loaded
        runNameDraft = loaded.name ?? "Honor Run 1"
        try? runStore.save(loaded)
        sharedRunToken = runStore.changeToken(for: loaded)
        reloadSavedRuns()
    }

    /// Checkpoint id → disposition, projected from the single walkthrough
    /// ledger. Steps without a ledger entry are pending.
    var checkpointDispositions: [String: CheckpointDisposition] {
        let ledger = run.walkthroughProgress ?? [:]
        var dispositions: [String: CheckpointDisposition] = [:]
        for step in walkthrough {
            guard let checkpointId = step.checkpointId else { continue }
            dispositions[checkpointId] = ledger[step.id] ?? .pending
        }
        return dispositions
    }

    var completedIds: [String] {
        checkpointDispositions.compactMap { $0.value.countsAsCompleted ? $0.key : nil }
    }

    var skippedIds: [String] {
        checkpointDispositions.compactMap { $0.value == .skipped ? $0.key : nil }
    }

    var currentRunName: String { run.name ?? "Honor Run" }

    var recommendedCheckpoint: RouteCheckpoint? {
        RunSafety.nextCheckpoint(route: route, dispositions: checkpointDispositions, selectedId: nil, partyLevel: lowestPartyLevel)
    }

    var recommendedWalkthroughStep: WalkthroughStep? {
        RunSafety.nextWalkthroughStep(
            walkthrough: walkthrough,
            walkthroughProgress: run.walkthroughProgress ?? [:],
            selectedCheckpointId: nil,
            walkthroughOutcomes: run.walkthroughOutcomes ?? [:],
            partyLevel: lowestPartyLevel
        )
    }

    func walkthroughBlockers(_ step: WalkthroughStep) -> [String] {
        RunSafety.dependencyBlockers(
            for: step,
            walkthrough: walkthrough,
            walkthroughProgress: run.walkthroughProgress ?? [:],
            walkthroughOutcomes: run.walkthroughOutcomes ?? [:]
        )
    }

    var currentWalkthroughBlockers: [String] {
        guard let step = currentWalkthroughStep else { return [] }
        return walkthroughBlockers(step)
    }

    var chatPrimaryBlocker: String? {
        if let dependency = currentWalkthroughBlockers.first { return dependency }
        guard let step = currentWalkthroughStep, step.minimumLevel > lowestPartyLevel else { return nil }
        return "Party L\(lowestPartyLevel); \(step.title) needs L\(step.minimumLevel)"
    }

    var focusedWalkthroughStep: WalkthroughStep? {
        guard let id = run.focusedWalkthroughStepId,
              let step = walkthrough.first(where: { $0.id == id }),
              walkthroughDisposition(step) == .pending else { return nil }
        return step
    }

    var currentWalkthroughStep: WalkthroughStep? {
        focusedWalkthroughStep
            ?? recommendedWalkthroughStep
            ?? activeWalkthroughSteps.min { $0.order < $1.order }
    }

    var currentCheckpoint: RouteCheckpoint? {
        if let step = currentWalkthroughStep {
            guard let checkpointId = step.checkpointId else { return nil }
            return route.first(where: { $0.id == checkpointId })
        }
        return recommendedCheckpoint
    }

    var activeWalkthroughSteps: [WalkthroughStep] {
        walkthrough.filter { walkthroughDisposition($0) == .pending }
    }

    var archivedWalkthroughSteps: [WalkthroughStep] {
        walkthrough.filter { walkthroughDisposition($0) != .pending }
    }

    var saferAlternative: WalkthroughStep? {
        guard let current = currentWalkthroughStep else { return nil }
        let unresolved = activeWalkthroughSteps.filter { $0.id != current.id && $0.minimumLevel <= lowestPartyLevel }
        let local = unresolved.filter { $0.region == current.region }
        let samePhase = unresolved.filter { $0.phaseOrder == current.phaseOrder }
        return (local.isEmpty ? samePhase : local).min {
            if $0.minimumLevel == $1.minimumLevel { return $0.order < $1.order }
            return $0.minimumLevel < $1.minimumLevel
        }
    }

    var assistantPhase: AssistantPhase {
        if combatCardPinned { return .combat }
        switch currentWalkthroughStep?.kind {
        case "dialogue", "decision": return .dialogue
        case "major_fight", "mini_fight": return .preflight
        default: return .explore
        }
    }

    var archivedCount: Int { archivedWalkthroughSteps.count }
    var remainingCount: Int { activeWalkthroughSteps.count }
    var routeHasConsequentialSkips: Bool {
        walkthrough.contains {
            walkthroughDisposition($0) == .skipped && $0.importance != "optional"
        }
    }

    var readinessHeadline: String {
        guard let readiness else { return currentCheckpoint == nil ? "NO FIGHT GATE" : "CHECKING" }
        return readiness.status == "danger" ? "DANGER" : readiness.status.uppercased()
    }

    var readinessDetail: String? {
        readiness?.blockers.first ?? readiness?.warnings.first ?? readiness?.nextActions.first
    }

    var combatPinLines: [String] {
        guard let checkpoint = currentCheckpoint else { return [] }
        let trigger = checkpoint.legendaryAction ?? checkpoint.failureConditions.first ?? checkpoint.advice
        let protect = checkpoint.failureConditions.dropFirst().first ?? currentActivityAvoid
        return ["TRIGGER · \(trigger)", "PROTECT · \(protect)", "EXIT · Keep one mobile survivor able to disengage." ]
    }

    func walkthroughDisposition(_ step: WalkthroughStep) -> CheckpointDisposition {
        RunSafety.walkthroughDisposition(step, walkthroughProgress: run.walkthroughProgress ?? [:])
    }

    func incidentProtocol(for step: WalkthroughStep) -> IncidentProtocol? {
        if let incident = step.incident { return incident }
        guard let checkpointId = step.checkpointId,
              let checkpoint = route.first(where: { $0.id == checkpointId }) else { return nil }
        return IncidentProtocol(
            trigger: checkpoint.failureConditions.first ?? "The encounter stops following the prepared plan.",
            safeActions: Array(checkpoint.preparation.prefix(3)),
            never: step.avoid.isEmpty ? checkpoint.advice : step.avoid,
            escape: "Preserve one character with mobility or invisibility and use the prepared exit if the encounter allows fleeing.",
            honorDelta: checkpoint.legendaryAction ?? "No additional Honor-only mechanic is recorded for this encounter.",
            postFight: [],
            authority: "guide_fact",
            sourceUrl: checkpoint.source.url
        )
    }

    var currentProgress: CheckpointProgress {
        guard let id = currentCheckpoint?.id else { return CheckpointProgress() }
        return run.progress[id] ?? CheckpointProgress()
    }

    var activeParty: [PartyMember] { run.activeParty }
    var roster: [PartyMember] { run.roster ?? run.party }
    var lowestPartyLevel: Int { activeParty.map(\.level).min() ?? 1 }
    var selectedAct: Int { run.selectedAct ?? 1 }
    var activeGuideLoaded: Bool { loadedGuideAct == selectedAct }
    var activeRouteAvailable: Bool { activeGuideLoaded && loadedRouteAvailable }
    var chatContextSnapshot: ChatContextSnapshot {
        ChatContextSnapshot(
            version: 2,
            scope: chatScope,
            guideVersion: run.guideVersion,
            selectedAct: selectedAct,
            mapRegion: run.mapRegion,
            routePhase: currentWalkthroughStep?.phase ?? recommendedWalkthroughStep?.phase ?? "unknown",
            recommendedStepId: recommendedWalkthroughStep?.id,
            focusedStepId: run.focusedWalkthroughStepId,
            walkthroughStatuses: (run.walkthroughProgress ?? [:]).mapValues(\.rawValue),
            walkthroughOutcomes: run.walkthroughOutcomes ?? [:],
            roster: roster,
            storyOutcomes: Array(run.storyOutcomes ?? []).sorted(),
            equippedByMember: (run.equippedByMember ?? [:]).mapValues { Array($0).sorted() },
            equipmentOwnershipKnown: run.equipmentOwnershipKnown ?? false
        )
    }
    var levelActivityPlan: LevelActivityPlan? {
        RunSafety.activityPlan(
            route: route,
            dispositions: checkpointDispositions,
            selectedId: nil,
            partyLevel: lowestPartyLevel
        )
    }
    var routeRecommendationReason: String? {
        guard let checkpoint = currentCheckpoint else { return nil }
        if focusedWalkthroughStep != nil || run.selectedCheckpointId != nil { return "Focused by you • \(RunSafety.routePhaseName(checkpoint))" }
        if checkpoint.minimumLevel > lowestPartyLevel {
            return "Your party is L\(lowestPartyLevel); this fight is safe at L\(checkpoint.minimumLevel). Earn XP on quests and safe fights first."
        }
        return "\(RunSafety.routePhaseName(checkpoint)) • best match for a L\(lowestPartyLevel) party"
    }
    var warningsSuppressed: Bool {
        if let snoozedUntil, snoozedUntil > .now { return true }
        guard let id = currentCheckpoint?.id else { return false }
        return run.mutedCheckpointIds?.contains(id) == true
    }

    var isCurrentCheckpointMuted: Bool {
        guard let id = currentCheckpoint?.id else { return false }
        return run.mutedCheckpointIds?.contains(id) == true
    }

    var actTwoBlockers: [String] {
        guard route.count == 19 else { return ["Act 1 guide data is incomplete or unavailable; do not advance."] }
        return RunSafety.actTwoBlockers(route: route, dispositions: checkpointDispositions)
    }

    func start() async {
        guard pollTask == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        // Do this before trusting /health. A stale frozen backend can answer
        // successfully while serving an older embedded guide after an update.
        if let runningHealth = await backendClient.healthDetails() {
            await backendProcess.retireUnownedBackend(runningHealth)
        }
        // The user typically grants access in System Settings and then returns
        // to BG3 (not this window), so app-activation alone is not enough — but
        // it is the fastest signal when they do come back here.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in await self?.handlePermissionReturn(activatedApp) }
        }
        plannerRequestObserver = NotificationCenter.default.addObserver(
            forName: .showPlannerRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showPlannerNow() }
        }
        // The welcome tour must show before BG3 or the guide is up, so a
        // first launch greets instead of sitting silent in the menu bar. The
        // debug-tab hook overrides it ("onboarding" forces the tour, any tab
        // suppresses it) so per-tab verification stays deterministic.
        let debugTab = ProcessInfo.processInfo.environment["BG3_ASSISTANT_DEBUG_TAB"]
        if let debugTab {
            onboardingStep = debugTab.lowercased() == "onboarding" ? .welcome : nil
        }
        if onboardingStep != nil {
            forceOverlay = true
            showOverlay = true
        }
        await refreshStatuses()
        await loadRouteIfNeeded()
        // Dev hook, like BG3_ASSISTANT_STATE_DIR: launch with the planner
        // already open on a tab (e.g. "route", "loadout") so the expanded
        // overlay can be exercised without synthetic input.
        if let debugTab {
            plannerTab = PlannerTab.allCases.first { $0.rawValue.lowercased() == debugTab.lowercased() } ?? .current
            overlayExpanded = true
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatuses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let plannerRequestObserver { NotificationCenter.default.removeObserver(plannerRequestObserver) }
        plannerRequestObserver = nil
        overlayController.hide()
        backendProcess.stop()
    }

    func launchBG3() {
        guard let url = URL(string: "steam://run/1086940") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the local map with view intent only. The run itself travels via
    /// the shared SQLite RunStore, which the app persists on every mutation —
    /// the URL never carries run state.
    func openLocalMap(buildId: String? = nil, item: String? = nil, level: Int? = nil) {
        Task {
            if !backendHealthy { await startBackend() }
            var components = URLComponents(string: "http://127.0.0.1:8787/map")
            var query: [URLQueryItem] = [
                URLQueryItem(name: "level", value: String(level ?? lowestPartyLevel)),
            ]
            if let buildId { query.append(URLQueryItem(name: "build", value: buildId)) }
            if let item {
                query.append(URLQueryItem(name: "item", value: item))
                query.append(URLQueryItem(name: "tab", value: "route"))
            } else if buildId != nil {
                query.append(URLQueryItem(name: "tab", value: "party"))
            } else {
                query.append(URLQueryItem(name: "tab", value: "walkthrough"))
            }
            components?.queryItems = query
            guard backendHealthy, let url = components?.url else {
                errorMessage = "The local backend is unavailable."
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    func startBackend() async {
        do {
            try backendProcess.startIfNeeded()
            for _ in 0..<20 {
                if await backendClient.health() {
                    backendHealthy = true
                    await loadRouteIfNeeded(force: true)
                    return
                }
                try await Task.sleep(for: .milliseconds(350))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCheckpoint(_ checkpoint: RouteCheckpoint) {
        run.focusedWalkthroughStepId = walkthrough.first(where: { $0.checkpointId == checkpoint.id })?.id
        run.selectedCheckpointId = checkpoint.id
        run.mapRegion = checkpoint.region
        persistRun()
        skipNoteDraft = run.progress[checkpoint.id]?.skipNote ?? ""
        combatCardPinned = false
        plannerTab = .current
        refreshReadiness()
    }

    func followRecommendedRoute() {
        run.focusedWalkthroughStepId = nil
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        refreshReadiness()
    }

    func setDisposition(_ disposition: CheckpointDisposition, note: String = "") {
        guard let checkpoint = currentCheckpoint else { return }
        // The checklist fields stay checkpoint-keyed; the disposition itself
        // lives only in the walkthrough ledger.
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        progress.skipNote = note
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        combatCardPinned = false
        guard let step = walkthrough.first(where: { $0.checkpointId == checkpoint.id }) else {
            // Every route checkpoint is owned by a walkthrough step (asserted
            // in the model checks); without one there is no ledger to write.
            assertionFailure("No walkthrough step owns checkpoint \(checkpoint.id)")
            persistRun()
            return
        }
        setWalkthroughDisposition(step, disposition)
    }

    func walkthroughOutcome(_ step: WalkthroughStep) -> String? {
        run.walkthroughOutcomes?[step.id]
    }

    /// Resolve a decision step by recording which option actually happened.
    /// The run may have diverged from the guide (Rolan can leave); the ledger
    /// records reality, not the recommendation.
    func resolveWalkthroughStep(_ step: WalkthroughStep, outcome: String) {
        guard !run.actLedgerIsLocked(selectedAct) else { return }
        var outcomes = run.walkthroughOutcomes ?? [:]
        outcomes[step.id] = outcome
        run.walkthroughOutcomes = outcomes
        setWalkthroughDisposition(step, .completed)
    }

    func setWalkthroughDisposition(_ step: WalkthroughStep, _ disposition: CheckpointDisposition) {
        guard !run.actLedgerIsLocked(selectedAct) else { return }
        var progress = run.walkthroughProgress ?? [:]
        if disposition == .pending {
            progress.removeValue(forKey: step.id)
            run.walkthroughOutcomes?.removeValue(forKey: step.id)
        }
        else { progress[step.id] = disposition }
        run.walkthroughProgress = progress
        if disposition != .pending, run.selectedCheckpointId == step.checkpointId {
            run.selectedCheckpointId = nil
        }
        if disposition == .pending {
            run.focusedWalkthroughStepId = step.id
        } else if run.focusedWalkthroughStepId == step.id {
            run.focusedWalkthroughStepId = nil
        }
        syncRegionToRecommendation()
        persistRun()
        refreshReadiness()
    }

    func focusWalkthroughStep(_ step: WalkthroughStep) {
        guard walkthroughDisposition(step) == .pending else { return }
        run.focusedWalkthroughStepId = step.id
        run.selectedCheckpointId = step.checkpointId
        run.mapRegion = step.region
        combatCardPinned = false
        persistRun()
        plannerTab = .current
        refreshReadiness()
    }

    func completeCurrentActivity() {
        switch currentGoal {
        case .target:
            completeGearTarget()
        case .laterAct:
            break
        case .checkpoint:
            requestDisposition(.completed)
        case .routeComplete:
            break
        case .step(let step):
            // Decision steps have no single "done" — the player must say which
            // way it went. Jump to the route step so they can pick the outcome.
            if step.decision != nil {
                plannerTab = .route
                focusedWalkthroughStepId = step.id
                overlayExpanded = true
                syncOverlay()
            } else if step.checkpointId != nil {
                requestDisposition(.completed)
            } else {
                setWalkthroughDisposition(step, .completed)
            }
        }
    }

    func skipCurrentActivity() {
        guard let step = currentWalkthroughStep else {
            requestDisposition(.skipped)
            return
        }
        if step.checkpointId != nil { requestDisposition(.skipped) }
        else { setWalkthroughDisposition(step, .skipped) }
    }

    func revisitCurrentActivity() {
        guard let step = currentWalkthroughStep else {
            requestDisposition(.pending)
            return
        }
        if step.checkpointId != nil { requestDisposition(.pending) }
        else { setWalkthroughDisposition(step, .pending) }
    }

    func requestDisposition(_ disposition: CheckpointDisposition) {
        guard let checkpoint = currentCheckpoint else { return }
        if disposition == .pending {
            setDisposition(.pending)
            return
        }
        if disposition == .completed {
            setDisposition(.completed)
            return
        }
        let reasons = checkpoint.irreversibleWarnings.isEmpty
            ? []
            : ["this checkpoint has irreversible or time-sensitive consequences"]
        if reasons.isEmpty {
            setDisposition(disposition, note: disposition == .skipped ? skipNoteDraft : "")
        } else {
            pendingDisposition = disposition
            confirmationMessage = "Confirm \(disposition.rawValue): \(reasons.joined(separator: "; "))."
        }
    }

    func confirmPendingDisposition() {
        guard let disposition = pendingDisposition else { return }
        pendingDisposition = nil
        confirmationMessage = nil
        setDisposition(disposition, note: disposition == .skipped ? skipNoteDraft : "")
    }

    func cancelPendingDisposition() {
        pendingDisposition = nil
        confirmationMessage = nil
    }

    func snoozeWarnings() { snoozedUntil = Date().addingTimeInterval(10 * 60) }

    func toggleMuteCurrentCheckpoint() {
        guard let id = currentCheckpoint?.id else { return }
        var muted = run.mutedCheckpointIds ?? []
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        run.mutedCheckpointIds = muted
        persistRun()
    }

    func syncRegionToRecommendation() {
        if let step = RunSafety.nextWalkthroughStep(
            walkthrough: walkthrough,
            walkthroughProgress: run.walkthroughProgress ?? [:],
            selectedCheckpointId: nil,
            partyLevel: lowestPartyLevel
        ) {
            run.mapRegion = step.region
            return
        }
        guard let checkpoint = RunSafety.nextCheckpoint(
            route: route,
            dispositions: checkpointDispositions,
            selectedId: nil,
            partyLevel: lowestPartyLevel
        ) else { return }
        run.mapRegion = checkpoint.region
    }

    func resetGuideContext(load: Bool = true) {
        guideLoadGeneration &+= 1
        invalidateChatRequests()
        loadingGuideAct = nil
        loadedGuideAct = nil
        loadedRouteAvailable = false
        route = []
        walkthrough = []
        timedEvents = []
        readiness = nil
        statusMessage = "Loading Act \(selectedAct) guide…"
        syncOverlay()
        if load { Task { await loadRouteIfNeeded() } }
    }

    func loadRouteIfNeeded(force: Bool = false) async {
        let requestedAct = selectedAct
        let requestedRunID = run.id
        guard force || loadedGuideAct != requestedAct else { return }
        guard force || loadingGuideAct != requestedAct else { return }
        guard backendHealthy else { return }
        guideLoadGeneration &+= 1
        let generation = guideLoadGeneration
        loadingGuideAct = requestedAct
        if force || loadedGuideAct != requestedAct {
            loadedGuideAct = nil
            loadedRouteAvailable = false
            route = []
            walkthrough = []
            timedEvents = []
            readiness = nil
        }
        statusMessage = "Loading Act \(requestedAct) guide…"
        defer {
            if generation == guideLoadGeneration {
                loadingGuideAct = nil
            }
        }
        do {
            let payload = try await backendClient.route(act: requestedAct)
            guard generation == guideLoadGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct,
                  payload.act == requestedAct else { return }
            availableGuideVersion = payload.guideVersion
            if !run.guideVersion.isEmpty, run.guideVersion != payload.guideVersion {
                startUpdatedRun(guideVersion: payload.guideVersion, availableBuilds: payload.builds)
                return
            }
            route = payload.checkpoints
            walkthrough = payload.walkthrough
            timedEvents = payload.timedEvents
            builds = payload.builds
            acts = payload.acts
            loadedGuideAct = payload.act
            loadedRouteAvailable = payload.routeAvailable
            if run.guideVersion.isEmpty {
                run.guideVersion = payload.guideVersion
            }
            migrateBuildAbilityScoresIfNeeded()
            run.migrateLegacyFightDispositions(walkthrough: payload.walkthrough)
            statusMessage = payload.routeAvailable
                ? "Act \(requestedAct) guide ready • \(walkthrough.count) walkthrough steps"
                : "Act \(requestedAct) route guidance is not available yet"
            persistRun()
            guard generation == guideLoadGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            // Non-fatal: an older bundled backend without /api/items just
            // leaves the picker without alternatives.
            if let items = try? await backendClient.items(),
               generation == guideLoadGeneration,
               requestedRunID == run.id,
               requestedAct == selectedAct {
                itemCatalog = items
            }
            refreshReadiness()
        } catch {
            guard generation == guideLoadGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            statusMessage = "Act \(requestedAct) guide unavailable — retrying…"
            errorMessage = "Could not load Act \(requestedAct) route: \(error.localizedDescription)"
        }
    }

    /// Local, synchronous derivation from loaded guide + run state; there is
    /// nothing to await, cancel, or fail.
    func refreshReadiness() {
        guard activeRouteAvailable, let checkpoint = currentCheckpoint else {
            readiness = nil
            return
        }
        readiness = RunSafety.assessReadiness(
            checkpoint: checkpoint,
            route: route,
            walkthrough: walkthrough,
            activeParty: activeParty,
            completedIds: Set(completedIds),
            checkedPreparation: currentProgress.checkedPreparation,
            walkthroughProgress: run.walkthroughProgress ?? [:],
            walkthroughOutcomes: run.walkthroughOutcomes ?? [:],
            builds: builds
        )
    }

    private func refreshStatuses() async {
        reloadSharedRunIfNeeded()
        let detection = detector.detect()
        gameDetected = detection.isRunning
        if gameWindowFrame != detection.windowFrame { gameWindowFrame = detection.windowFrame }
        let health = await backendClient.healthDetails()
        backendHealthy = health?.ok == true
        backendAIAvailable = health?.aiAvailable == true
        if !backendHealthy { await startBackend() }
        await loadRouteIfNeeded()
        // One-time hints fire at the moment of relevance: basics the first
        // time the game is seen, fight tools the first pre-fight moment.
        if gameDetected, !overlayExpanded {
            maybeShowHint(.peekBasics)
            if assistantPhase == .preflight { maybeShowHint(.fightTools) }
        }
        syncOverlay()
    }

}

enum BG3AssistantError: LocalizedError, Equatable {
    case bg3WindowNotFound
    case imageEncodingFailed
    case invalidBackendResponse

    var errorDescription: String? {
        switch self {
        case .bg3WindowNotFound: "Could not find a Baldur's Gate 3 window to capture."
        case .imageEncodingFailed: "Could not encode the BG3 screenshot."
        case .invalidBackendResponse: "The BG3 assistant backend returned an invalid response."
        }
    }
}
