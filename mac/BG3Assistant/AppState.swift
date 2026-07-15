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
    @Published var gameName = "Not detected"
    @Published var gameDetectionDetail = "Not checked yet"
    @Published var backendHealthy = false
    @Published var backendStatus = "Not checked yet"
    @Published var openRouterKeyDraft = ""
    @Published private(set) var hasOpenRouterKey = OpenRouterKeyStore.load() != nil
    @Published private(set) var openRouterKeyStatus = OpenRouterKeyStore.load() == nil
        ? "Optional for AI chat"
        : "Saved in macOS Keychain"
    @Published var showOverlay = true { didSet { syncOverlay() } }
    @Published var forceOverlay = false { didSet { syncOverlay() } }
    @Published var overlayExpanded = false { didSet { syncOverlay() } }
    @Published var plannerTab: PlannerTab = .current { didSet { if overlayExpanded { syncOverlay() } } }
    @Published var overlayDensity = OverlayDensity(
        rawValue: storedSettings.overlayDensity
    ) ?? .focus {
        didSet {
            persistSettings()
            syncOverlay()
        }
    }
    @Published var hotkeyPeekActive = false { didSet { syncOverlay() } }
    // Route step to scroll to and expand when the route tab opens (set by the
    // peek card's Talk shortcut so the current conversation is front and center).
    @Published var focusedWalkthroughStepId: String?
    @Published var route: [RouteCheckpoint] = []
    @Published var walkthrough: [WalkthroughStep] = []
    @Published var builds: [BuildSummary] = []
    @Published var run: HonorRun
    @Published var readiness: ReadinessResponse?
    @Published var isLoading = false
    @Published var statusMessage = "Loading Act 1 guide…"
    @Published var errorMessage: String?
    @Published var chatDraft = ""
    @Published var chatLines: [ChatLine] = []
    @Published var chatScreenshot: ScreenshotResult?
    @Published var isPreparingChatScreenshot = false
    @Published var chatScope: ChatScope = .current
    @Published var skipNoteDraft = ""
    @Published var pendingDisposition: CheckpointDisposition?
    @Published var confirmationMessage: String?
    @Published var pendingRosterStatusChange: PendingRosterStatusChange?
    @Published var combatCardPinned = false
    @Published var snoozedUntil: Date?
    @Published var availableGuideVersion = ""
    @Published var newRunConfirmation = false
    @Published private(set) var savedRuns: [SavedRunSummary] = []
    @Published var runNameDraft = ""
    @Published var newRunNameDraft = ""
    @Published var screenCaptureVerifiedThisLaunch = false
    @Published var showScreenRecordingPermissionPrompt = false

    private let detector = BG3Detector()
    let backendClient = BackendClient()
    private let backendProcess = BackendProcessManager()
    let captureService = ScreenCaptureService()
    private let runStore = RunStore()
    private let globalPeekHotKey = GlobalPeekHotKey()
    private let overlayController = OverlayPanelController()
    private var isStarting = false
    private var pollTask: Task<Void, Never>?
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

    init() {
        var loaded = runStore.load()
        loaded.migrateLegacyPartySlots()
        if loaded.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            loaded.name = "Honor Run 1"
        }
        if loaded.createdAt == nil { loaded.createdAt = .now }
        run = loaded
        focusedWalkthroughStepId = loaded.focusedWalkthroughStepId
        runNameDraft = loaded.name ?? "Honor Run 1"
        try? runStore.save(loaded)
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
        checkpointDispositions.compactMap { $0.value == .completed ? $0.key : nil }
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
        focusedWalkthroughStep ?? recommendedWalkthroughStep
    }

    var currentCheckpoint: RouteCheckpoint? {
        if let focused = focusedWalkthroughStep {
            guard let checkpointId = focused.checkpointId else { return nil }
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

    var effectiveOverlayDensity: OverlayDensity {
        hotkeyPeekActive ? .focus : overlayDensity
    }

    var currentDialogueStep: WalkthroughStep? {
        if let focusedWalkthroughStep,
           focusedWalkthroughStep.kind == "dialogue" || focusedWalkthroughStep.kind == "decision" {
            return focusedWalkthroughStep
        }
        return RunSafety.nextDialogueStep(
            walkthrough: walkthrough,
            walkthroughProgress: run.walkthroughProgress ?? [:],
            selectedCheckpointId: run.selectedCheckpointId,
            partyLevel: lowestPartyLevel
        )
    }

    var currentActivityTitle: String { currentWalkthroughStep?.title ?? currentCheckpoint?.name ?? "Act 1 complete" }
    var currentActivityArea: String { currentWalkthroughStep?.area ?? currentCheckpoint?.area ?? "" }
    var currentActivityMinimumLevel: Int { currentWalkthroughStep?.minimumLevel ?? currentCheckpoint?.minimumLevel ?? lowestPartyLevel }
    var currentActivityAvoid: String {
        return currentWalkthroughStep?.incident?.never
            ?? currentWalkthroughStep?.avoid
            ?? currentCheckpoint?.failureConditions.first
            ?? currentCheckpoint?.advice
            ?? "Review the Act 2 gate before advancing."
    }
    var currentActivityDanger: String {
        if let checkpointId = currentWalkthroughStep?.checkpointId,
           let danger = route.first(where: { $0.id == checkpointId })?.danger { return danger }
        if currentWalkthroughStep?.incident != nil { return "high" }
        return currentWalkthroughStep?.kind == "dialogue" ? "medium" : (currentCheckpoint?.danger ?? "low")
    }
    var currentActivityLabel: String {
        if assistantPhase == .combat { return AssistantPhase.combat.rawValue }
        switch currentWalkthroughStep?.kind {
        case "dialogue", "decision": return "DIALOGUE"
        case "pickup": return "PICKUP"
        case "exploration": return "EXPLORE"
        case "gate": return "READINESS GATE"
        case "major_fight": return "MAIN FIGHT"
        case "mini_fight": return "SAFE FIGHT"
        default: return levelActivityPlan?.activityLabel ?? "NEXT"
        }
    }

    var archivedCount: Int { archivedWalkthroughSteps.count }
    var remainingCount: Int { activeWalkthroughSteps.count }

    var readinessHeadline: String {
        guard let readiness else { return currentCheckpoint == nil ? "NO FIGHT GATE" : "CHECKING" }
        let status = readiness.status == "danger" ? "BLOCKED" : readiness.status.uppercased()
        let total = currentCheckpoint?.preparation.count ?? 0
        let checked = currentProgress.checkedPreparation.count
        return total > 0 ? "\(status) · PREP \(checked)/\(total)" : status
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
    var guideUpdateNotice: String? {
        guard !availableGuideVersion.isEmpty, !run.guideVersion.isEmpty, availableGuideVersion != run.guideVersion else { return nil }
        return "Run pinned to guide \(run.guideVersion); \(availableGuideVersion) is available. Start a new run to adopt it."
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
            await backendProcess.retireUnownedPackagedBackend(runningHealth)
        }
        globalPeekHotKey.start { [weak self] pressed in
            Task { @MainActor in self?.hotkeyPeekActive = pressed }
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
        await refreshStatuses()
        await loadRouteIfNeeded()
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
        overlayController.hide()
        globalPeekHotKey.stop()
        backendProcess.stop()
    }

    func launchBG3() {
        guard let url = URL(string: "steam://run/1086940") else { return }
        NSWorkspace.shared.open(url)
    }

    func openActOneMap(buildId: String? = nil, item: String? = nil, level: Int? = nil) {
        Task {
            if !backendHealthy { await startBackend() }
            var components = URLComponents(string: "http://127.0.0.1:8787/map")
            let partyBuilds = activeParty.compactMap(\.buildId)
            var query: [URLQueryItem] = [
                URLQueryItem(name: "act", value: String(selectedAct)),
                URLQueryItem(name: "level", value: String(level ?? lowestPartyLevel)),
                URLQueryItem(name: "builds", value: partyBuilds.joined(separator: ",")),
                URLQueryItem(name: "done", value: completedIds.joined(separator: ",")),
            ]
            if let partyData = try? JSONEncoder().encode(activeParty),
               let partyJSON = String(data: partyData, encoding: .utf8) {
                query.append(URLQueryItem(name: "party", value: partyJSON))
            }
            if let rosterData = try? JSONEncoder().encode(roster),
               let rosterJSON = String(data: rosterData, encoding: .utf8) {
                query.append(URLQueryItem(name: "roster", value: rosterJSON))
            }
            if let walkthroughData = try? JSONEncoder().encode(run.walkthroughProgress ?? [:]),
               let walkthroughJSON = String(data: walkthroughData, encoding: .utf8) {
                query.append(URLQueryItem(name: "walkthrough", value: walkthroughJSON))
            }
            if let equipmentData = try? JSONEncoder().encode(run.equippedByMember ?? [:]),
               let equipmentJSON = String(data: equipmentData, encoding: .utf8) {
                query.append(URLQueryItem(name: "equipped", value: equipmentJSON))
            }
            if let outcomeData = try? JSONEncoder().encode(Array(run.storyOutcomes ?? []).sorted()),
               let outcomeJSON = String(data: outcomeData, encoding: .utf8) {
                query.append(URLQueryItem(name: "storyOutcomes", value: outcomeJSON))
            }
            query.append(URLQueryItem(name: "includeCamp", value: (run.includeCampPlans ?? false) ? "true" : "false"))
            if let focus = run.focusedWalkthroughStepId {
                query.append(URLQueryItem(name: "focus", value: focus))
            }
            if let buildId { query.append(URLQueryItem(name: "build", value: buildId)) }
            if let item {
                query.append(URLQueryItem(name: "item", value: item))
                query.append(URLQueryItem(name: "tab", value: "route"))
            } else if buildId != nil {
                query.append(URLQueryItem(name: "tab", value: "party"))
            } else {
                query.append(URLQueryItem(name: "tab", value: "walkthrough"))
            }
            components?.queryItems = query.isEmpty ? nil : query
            guard backendHealthy, let url = components?.url else {
                errorMessage = "The local backend is unavailable."
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    func startBackend() async {
        backendStatus = "Starting backend…"
        do {
            try backendProcess.startIfNeeded(openRouterAPIKey: OpenRouterKeyStore.load())
            for _ in 0..<20 {
                if await backendClient.health() {
                    backendHealthy = true
                    backendStatus = "OK"
                    await loadRouteIfNeeded(force: true)
                    return
                }
                try await Task.sleep(for: .milliseconds(350))
            }
            backendStatus = "Process started; /health not ready"
        } catch {
            backendStatus = "Start failed"
            errorMessage = error.localizedDescription
        }
    }

    func togglePlanner() {
        overlayExpanded.toggle()
    }

    func showOverlayNow() {
        forceOverlay = true
        showOverlay = true
        syncOverlay()
    }

    func showPlannerNow() {
        plannerTab = .current
        forceOverlay = true
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func openSettings() {
        plannerTab = .settings
        forceOverlay = true
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func openDialogue() {
        // Dialogue lives inside the route now: jump to the route with the
        // current conversation step focused and expanded.
        plannerTab = .route
        focusedWalkthroughStepId = currentDialogueStep?.id ?? currentWalkthroughStep?.id
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func hideAssistantOverlay() {
        forceOverlay = false
        showOverlay = false
    }

    func selectCheckpoint(_ checkpoint: RouteCheckpoint) {
        run.focusedWalkthroughStepId = walkthrough.first(where: { $0.checkpointId == checkpoint.id })?.id
        focusedWalkthroughStepId = run.focusedWalkthroughStepId
        run.selectedCheckpointId = checkpoint.id
        run.mapRegion = checkpoint.region
        persistRun()
        skipNoteDraft = run.progress[checkpoint.id]?.skipNote ?? ""
        combatCardPinned = false
        plannerTab = .current
        Task { await refreshReadiness() }
    }

    func followRecommendedRoute() {
        run.focusedWalkthroughStepId = nil
        focusedWalkthroughStepId = nil
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        Task { await refreshReadiness() }
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
        var outcomes = run.walkthroughOutcomes ?? [:]
        outcomes[step.id] = outcome
        run.walkthroughOutcomes = outcomes
        setWalkthroughDisposition(step, .completed)
    }

    func setWalkthroughDisposition(_ step: WalkthroughStep, _ disposition: CheckpointDisposition) {
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
            focusedWalkthroughStepId = step.id
        } else {
            if run.focusedWalkthroughStepId == step.id {
                run.focusedWalkthroughStepId = nil
                focusedWalkthroughStepId = nil
            }
        }
        syncRegionToRecommendation()
        persistRun()
        Task { await refreshReadiness() }
    }

    func focusWalkthroughStep(_ step: WalkthroughStep) {
        guard walkthroughDisposition(step) == .pending else { return }
        run.focusedWalkthroughStepId = step.id
        focusedWalkthroughStepId = step.id
        run.selectedCheckpointId = step.checkpointId
        run.mapRegion = step.region
        combatCardPinned = false
        persistRun()
        plannerTab = .current
        Task { await refreshReadiness() }
    }

    func completeCurrentActivity() {
        guard let step = currentWalkthroughStep else {
            requestDisposition(.completed)
            return
        }
        // Decision steps have no single "done" — the player must say which
        // way it went. Jump to the route step so they can pick the outcome.
        if step.decision != nil {
            plannerTab = .route
            focusedWalkthroughStepId = step.id
            overlayExpanded = true
            syncOverlay()
            return
        }
        if step.checkpointId != nil { requestDisposition(.completed) }
        else { setWalkthroughDisposition(step, .completed) }
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
        var reasons: [String] = []
        if disposition == .completed {
            reasons = RunSafety.completionConfirmationReasons(
                checkpoint: checkpoint,
                progress: currentProgress,
                readinessStatus: readiness?.status
            )
        } else if !checkpoint.irreversibleWarnings.isEmpty {
            reasons.append("this checkpoint has irreversible or time-sensitive consequences")
        }
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

    func pinCurrentFight() {
        guard currentCheckpoint != nil, readiness?.status != "blocked" else { return }
        combatCardPinned = true
        overlayExpanded = false
    }

    func unpinFight() { combatCardPinned = false }

    func snoozeWarnings() { snoozedUntil = Date().addingTimeInterval(10 * 60) }

    func toggleMuteCurrentCheckpoint() {
        guard let id = currentCheckpoint?.id else { return }
        var muted = run.mutedCheckpointIds ?? []
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        run.mutedCheckpointIds = muted
        persistRun()
    }

    func startNewRun() {
        var fresh = HonorRun()
        let requestedName = newRunNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        fresh.name = requestedName.isEmpty ? "Honor Run \(savedRuns.count + 1)" : requestedName
        fresh.createdAt = .now
        fresh.migrateLegacyPartySlots()
        fresh.guideVersion = availableGuideVersion
        run = fresh
        runNameDraft = fresh.name ?? "Honor Run"
        newRunNameDraft = ""
        skipNoteDraft = ""
        combatCardPinned = false
        focusedWalkthroughStepId = nil
        chatLines = []
        chatScreenshot = nil
        persistRun()
        reloadSavedRuns()
        Task { await refreshReadiness() }
    }

    func renameCurrentRun() {
        let name = runNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run.name = name
        persistRun()
        reloadSavedRuns()
    }

    func switchRun(to runID: String) {
        guard runID != run.id else { return }
        persistRun()
        do {
            var selected = try runStore.activate(runID: runID)
            selected.migrateLegacyPartySlots()
            run = selected
            runNameDraft = selected.name ?? "Honor Run"
            focusedWalkthroughStepId = selected.focusedWalkthroughStepId
            skipNoteDraft = ""
            combatCardPinned = false
            chatLines = []
            chatScreenshot = nil
            reloadSavedRuns()
            Task { await refreshReadiness() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setSelectedAct(_ act: Int) {
        guard (1...3).contains(act) else { return }
        run.selectedAct = act
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

    private func loadRouteIfNeeded(force: Bool = false) async {
        guard force || route.isEmpty else { return }
        guard backendHealthy else { return }
        do {
            let payload = try await backendClient.route()
            route = payload.checkpoints
            walkthrough = payload.walkthrough
            builds = payload.builds
            availableGuideVersion = payload.guideVersion
            if run.guideVersion.isEmpty { run.guideVersion = payload.guideVersion }
            run.migrateLegacyFightDispositions(walkthrough: payload.walkthrough)
            statusMessage = "Act 1 guide ready • \(walkthrough.count) walkthrough steps"
            persistRun()
            await refreshReadiness()
        } catch { errorMessage = "Could not load Act 1 route: \(error.localizedDescription)" }
    }

    func refreshReadiness() async {
        guard backendHealthy, let checkpoint = currentCheckpoint else { readiness = nil; return }
        do {
            readiness = try await backendClient.readiness(ReadinessRequest(
                checkpointId: checkpoint.id,
                party: activeParty,
                completedCheckpointIds: completedIds,
                checkedPreparation: Array(currentProgress.checkedPreparation)
            ))
        } catch { errorMessage = "Readiness check failed: \(error.localizedDescription)" }
    }

    private func refreshStatuses() async {
        let detection = detector.detect()
        gameDetected = detection.isRunning
        gameName = detection.displayName
        gameDetectionDetail = detection.detail
        if gameWindowFrame != detection.windowFrame { gameWindowFrame = detection.windowFrame }
        backendHealthy = await backendClient.health()
        backendStatus = backendHealthy ? "OK" : (backendProcess.isRunning ? "Process running, /health offline" : "Offline")
        if !backendHealthy { await startBackend() }
        await loadRouteIfNeeded()
        syncOverlay()
    }

    func persistRun() {
        do {
            try runStore.save(run)
            reloadSavedRuns()
        }
        catch { errorMessage = "Could not save run: \(error.localizedDescription)" }
    }

    private func reloadSavedRuns() {
        savedRuns = runStore.listRuns().map { saved in
            SavedRunSummary(
                id: saved.id,
                name: saved.name ?? "Honor Run",
                completedSteps: saved.walkthroughProgress?.values.filter { $0 == .completed }.count ?? 0,
                partyLevel: saved.activeParty.map(\.level).min() ?? 1
            )
        }
    }

    private func persistSettings() {
        let settings = AssistantSettings(
            overlayDensity: overlayDensity.rawValue
        )
        do { try runStore.saveSettings(settings) }
        catch { errorMessage = "Could not save settings: \(error.localizedDescription)" }
    }

    func saveOpenRouterKey() async {
        let key = openRouterKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Enter an OpenRouter key first."
            return
        }
        do {
            try OpenRouterKeyStore.save(key)
            openRouterKeyDraft = ""
            hasOpenRouterKey = true
            openRouterKeyStatus = "Saved in macOS Keychain"
            errorMessage = nil
            await restartBackendForOpenRouterKey()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeOpenRouterKey() async {
        OpenRouterKeyStore.remove()
        openRouterKeyDraft = ""
        hasOpenRouterKey = false
        chatScreenshot = nil
        openRouterKeyStatus = "Optional for AI chat"
        await restartBackendForOpenRouterKey()
    }

    private func restartBackendForOpenRouterKey() async {
        backendProcess.stop()
        backendHealthy = false
        backendStatus = "Restarting backend…"
        for _ in 0..<20 {
            if !(await backendClient.health()) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await startBackend()
    }

    func syncOverlay() {
        if showOverlay && (gameDetected || forceOverlay) { overlayController.show(appState: self, gameFrame: gameWindowFrame) }
        else { overlayController.hide() }
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
