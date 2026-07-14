import AppKit
import Foundation

struct ChatLine: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    private static let storedSettings = RunStore().loadSettings()

    @Published var gameDetected = false
    @Published var gameName = "Not detected"
    @Published var gameDetectionDetail = "Not checked yet"
    @Published var backendHealthy = false
    @Published var backendStatus = "Not checked yet"
    @Published var telemetryEnabled = storedSettings.telemetryEnabled {
        didSet {
            persistSettings()
            if !telemetryEnabled { telemetryStatus = nil }
        }
    }
    @Published var telemetryStatus: TelemetryStatus?
    @Published var visualMemoryEnabled = storedSettings.visualMemoryEnabled {
        didSet {
            persistSettings()
            if !visualMemoryEnabled { visualMemoryStatus = "Off" }
            Task { await automaticCapturePreferenceChanged() }
        }
    }
    @Published var mapOverlayCaptureEnabled = storedSettings.mapOverlayCaptureEnabled {
        didSet {
            persistSettings()
            if !mapOverlayCaptureEnabled {
                isMapOpen = false
                mapDetectionStatus = "Off"
                mapOverlayController.hide()
            }
            Task { await automaticCapturePreferenceChanged() }
        }
    }
    @Published var visualMemoryStatus = "Off"
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
    @Published var latestResponse: AnalysisResponse?
    @Published var latestScreenshotSize = "none"
    @Published var latestLatencyMs = 0
    @Published var isMapOpen = false
    @Published var mapDetectionStatus = "Off"
    @Published var mapDetectionConfidence = 0.0
    @Published var latestLocalDetectionTimestamp: TimeInterval?
    @Published var chatDraft = ""
    @Published var chatLines: [ChatLine] = []
    @Published var chatScope: ChatScope = .current
    @Published var skipNoteDraft = ""
    @Published var pendingDisposition: CheckpointDisposition?
    @Published var confirmationMessage: String?
    @Published var pendingRosterStatusChange: PendingRosterStatusChange?
    @Published var combatCardPinned = false
    @Published var snoozedUntil: Date?
    @Published var availableGuideVersion = ""
    @Published var newRunConfirmation = false
    @Published var screenRecordingPreflightAllowed = PermissionManager.hasScreenRecordingPermission
    @Published var screenRecordingPreflightStatus = PermissionManager.hasScreenRecordingPermission ? "Granted by macOS" : "Not granted by macOS"
    @Published var screenRecordingAllowed = PermissionManager.hasScreenRecordingPermission
    @Published var screenRecordingStatus = PermissionManager.hasScreenRecordingPermission ? "Granted by macOS" : "Not granted by macOS"
    @Published var shouldShowScreenRecordingHelp = false
    @Published var screenCaptureLastError: String?
    @Published var screenCaptureVerifiedThisLaunch = false
    @Published var screenCaptureVerificationStatus = PermissionManager.hasScreenRecordingPermission ? "Automatic check pending" : "Waiting for permission"
    @Published var screenCaptureRequestStatus = "Not requested this launch"
    @Published var showScreenRecordingPermissionPrompt = false
    @Published var appPermissionIdentity = PermissionManager.appIdentityDescription
    let appPermissionInstallStatus = PermissionManager.installationDescription
    let appInstalledInApplications = PermissionManager.isInstalledInApplications

    private let detector = BG3Detector()
    private let backendClient = BackendClient()
    private let backendProcess = BackendProcessManager()
    private let captureService = ScreenCaptureService()
    private let mapDetector = MapOpenDetector()
    private let runStore = RunStore()
    private let globalPeekHotKey = GlobalPeekHotKey()
    private let overlayController = OverlayPanelController()
    private let mapOverlayController = MapMarkerOverlayPanelController()
    private var isStarting = false
    private var pollTask: Task<Void, Never>?
    private var automaticCaptureTask: Task<Void, Never>?
    private var lastAutomaticCaptureAt = Date.distantPast
    private var automaticCaptureInFlight = false
    private var detectedWindowFrame: CGRect?
    @Published private(set) var gameWindowFrame: CGRect?

    // Capture permission has three intentionally separate signals: raw TCC
    // preflight, a successful pixel capture, and whether this launch already
    // invoked the registration request. Never infer one from another.
    private var captureAuthorized = false
    private var permissionRequestAttemptedThisLaunch = false
    private var permissionProbeAfterSettings = false
    private var captureAuthorizationRefreshInFlight = false
    private var lastCaptureProbe = Date.distantPast
    private var activationObserver: Any?

    init() {
        var loaded = runStore.load()
        loaded.migrateLegacyPartySlots()
        run = loaded
        focusedWalkthroughStepId = loaded.focusedWalkthroughStepId
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

    var telemetryActive: Bool { telemetryEnabled && telemetryStatus?.active == true }
    var telemetryModeLabel: String {
        guard telemetryEnabled else { return "Vanilla • no mod required" }
        guard let telemetryStatus else { return "Vanilla fallback • waiting for Live Events" }
        return telemetryStatus.active ? telemetryStatus.message : "Vanilla fallback • \(telemetryStatus.message)"
    }
    var telemetrySuggestion: TelemetrySuggestion? {
        telemetryActive ? TelemetryGuidance.latestSuggestion(in: telemetryStatus) : nil
    }
    var automaticCaptureEnabled: Bool { visualMemoryEnabled || mapOverlayCaptureEnabled }
    var latestVisualMemory: VisualMemoryEntry? { run.visualMemory?.last }
    var unresolvedVisualCompletionCandidates: [VisualCompletionCandidate] {
        guard let latestVisualMemory else { return [] }
        return latestVisualMemory.completionCandidates.filter { candidate in
            candidate.confidence >= 0.80
                && walkthrough.first(where: { $0.id == candidate.stepId }).map { walkthroughDisposition($0) == .pending } == true
        }
    }
    var visualMemoryAgeLabel: String {
        guard let capturedAt = latestVisualMemory?.capturedAt else { return "No observations yet" }
        let seconds = max(0, Int(Date().timeIntervalSince(capturedAt)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

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
        if latestResponse?.detected.screenKind == "level_up" { return .levelUp }
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
    var loadoutMembers: [PartyMember] {
        (run.includeCampPlans ?? false)
            ? roster.filter { [.active, .camp].contains($0.rosterStatus) }
            : activeParty
    }
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
            detectionTimestamp: latestVisualMemory?.capturedAt.timeIntervalSince1970 ?? latestLocalDetectionTimestamp,
            detectionConfidence: latestVisualMemory?.confidence ?? (latestLocalDetectionTimestamp == nil ? nil : mapDetectionConfidence),
            recommendedStepId: recommendedWalkthroughStep?.id,
            focusedStepId: run.focusedWalkthroughStepId,
            walkthroughStatuses: (run.walkthroughProgress ?? [:]).mapValues(\.rawValue),
            walkthroughOutcomes: run.walkthroughOutcomes ?? [:],
            roster: roster,
            storyOutcomes: Array(run.storyOutcomes ?? []).sorted(),
            equippedByMember: (run.equippedByMember ?? [:]).mapValues { Array($0).sorted() },
            equipmentOwnershipKnown: run.equipmentOwnershipKnown ?? false,
            visualMemorySummary: latestVisualMemory?.summary,
            visualMemoryTimestamp: latestVisualMemory?.capturedAt.timeIntervalSince1970,
            visualMemoryCompletionStepIds: unresolvedVisualCompletionCandidates.map(\.stepId)
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
        // Automatic capture is opt-in. Do not probe pixels or request Screen
        // Recording on startup when both Visual Memory and map alignment are off.
        if automaticCaptureEnabled {
            await refreshCaptureAuthorization(force: true, promptIfMissing: true)
        } else {
            updateCapturePreflight(PermissionManager.hasScreenRecordingPermission)
            screenRecordingStatus = PermissionManager.hasScreenRecordingPermission
                ? "Granted by macOS • monitoring off"
                : "Optional • monitoring off"
            screenCaptureVerificationStatus = "Not checked • monitoring off"
            shouldShowScreenRecordingHelp = false
        }
        await refreshStatuses()
        await loadRouteIfNeeded()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatuses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        automaticCaptureTask = Task { [weak self] in
            while !Task.isCancelled {
                let cycleStarted = Date()
                await self?.sampleAutomaticScreen()
                let elapsed = Date().timeIntervalSince(cycleStarted)
                let remainingMilliseconds = max(100, Int((30 - elapsed) * 1000))
                try? await Task.sleep(for: .milliseconds(remainingMilliseconds))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        automaticCaptureTask?.cancel()
        pollTask = nil
        automaticCaptureTask = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        overlayController.hide()
        mapOverlayController.hide()
        globalPeekHotKey.stop()
        backendProcess.stop()
    }

    func refreshCaptureAuthorization(force: Bool = false, promptIfMissing: Bool = false) async {
        guard !captureAuthorizationRefreshInFlight else { return }
        captureAuthorizationRefreshInFlight = true
        defer { captureAuthorizationRefreshInFlight = false }

        let preflightGranted = PermissionManager.hasScreenRecordingPermission
        updateCapturePreflight(preflightGranted)
        let action = PermissionManager.authorizationAction(
            preflightGranted: preflightGranted,
            verifiedThisLaunch: screenCaptureVerifiedThisLaunch,
            requestAttempted: permissionRequestAttemptedThisLaunch,
            promptIfMissing: promptIfMissing
        )
        switch action {
        case .alreadyVerified:
            applyCaptureAuthorization(true, verifiedByPixels: true)
        case .offerRequest:
            applyCaptureAuthorization(false, verifiedByPixels: false)
            showScreenRecordingPermissionPrompt = true
        case .verifyPixels:
            guard force || Date().timeIntervalSince(lastCaptureProbe) > 4 else { return }
            lastCaptureProbe = Date()
            let verified = await PermissionManager.verifyScreenRecordingAccess()
            if verified {
                applyCaptureAuthorization(true, verifiedByPixels: true)
            } else if promptIfMissing && !permissionRequestAttemptedThisLaunch {
                applyCaptureAuthorization(false, verifiedByPixels: false)
                showScreenRecordingPermissionPrompt = true
            } else {
                applyCaptureAuthorization(false, verifiedByPixels: false)
            }
        case .wait:
            applyCaptureAuthorization(false, verifiedByPixels: false)
        }
    }

    private func updateCapturePreflight(_ granted: Bool) {
        screenRecordingPreflightAllowed = granted
        screenRecordingPreflightStatus = granted ? "Granted by macOS" : "Not granted by macOS"
    }

    private func applyCaptureAuthorization(_ authorized: Bool, verifiedByPixels: Bool) {
        captureAuthorized = authorized
        screenRecordingAllowed = authorized
        if authorized {
            if verifiedByPixels { screenCaptureVerifiedThisLaunch = true }
            screenRecordingStatus = verifiedByPixels ? "Granted • pixel capture verified" : "Granted"
            screenCaptureVerificationStatus = verifiedByPixels ? "Pixel access verified" : "Granted • verifying capture"
            shouldShowScreenRecordingHelp = false
            screenCaptureLastError = nil
        } else {
            screenCaptureVerifiedThisLaunch = false
            screenRecordingStatus = "Not granted by macOS"
            screenCaptureVerificationStatus = "Waiting for permission"
            shouldShowScreenRecordingHelp = true
        }
    }

    private func automaticCapturePreferenceChanged() async {
        guard automaticCaptureEnabled else {
            visualMemoryStatus = "Off"
            isMapOpen = false
            mapDetectionStatus = "Off"
            mapOverlayController.hide()
            return
        }
        await refreshCaptureAuthorization(force: true, promptIfMissing: true)
        guard captureAuthorized || screenCaptureVerifiedThisLaunch else {
            if visualMemoryEnabled { visualMemoryStatus = "Waiting for Screen Recording" }
            if mapOverlayCaptureEnabled { mapDetectionStatus = "Waiting for Screen Recording" }
            return
        }
        await sampleAutomaticScreen(force: true)
    }

    private func prepareCaptureForUserAction() async -> Bool {
        await refreshCaptureAuthorization(force: true, promptIfMissing: true)
        return captureAuthorized || screenCaptureVerifiedThisLaunch
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
            try backendProcess.startIfNeeded()
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
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func showPlannerForSetup() {
        forceOverlay = true
        showPlannerNow()
    }

    func showPartyLoadout() {
        forceOverlay = true
        plannerTab = .loadout
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func openChat() {
        plannerTab = .chat
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
        fresh.migrateLegacyPartySlots()
        fresh.guideVersion = availableGuideVersion
        run = fresh
        skipNoteDraft = ""
        combatCardPinned = false
        focusedWalkthroughStepId = nil
        latestResponse = nil
        chatLines = []
        persistRun()
        Task { await refreshReadiness() }
    }

    func togglePreparation(_ item: String) {
        guard let checkpoint = currentCheckpoint else { return }
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        if progress.checkedPreparation.contains(item) { progress.checkedPreparation.remove(item) }
        else { progress.checkedPreparation.insert(item) }
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        persistRun()
        Task { await refreshReadiness() }
    }

    func toggleCompletion(_ item: String) {
        guard let checkpoint = currentCheckpoint else { return }
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        if progress.checkedCompletion.contains(item) { progress.checkedCompletion.remove(item) }
        else { progress.checkedCompletion.insert(item) }
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        persistRun()
    }

    func updatePartyMember(_ member: PartyMember) {
        guard let index = run.roster?.firstIndex(where: { $0.id == member.id }) else { return }
        run.roster?[index] = member
        run.syncActivePartyProjection()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        Task { await refreshReadiness() }
    }

    @discardableResult
    func setRosterStatus(_ status: RosterStatus, for member: PartyMember, confirmed: Bool = false) -> Bool {
        if status == .active, !member.rosterStatus.canBeActive {
            errorMessage = "Confirm that \(member.name) is available again before adding them to the active party."
            return false
        }
        if [.dead, .departed].contains(status), member.rosterStatus != status, !confirmed {
            let impact = member.rosterStatus == .active
                ? "They will stop contributing to readiness and route-level guidance."
                : "They will remain outside active readiness."
            let plan = member.buildId == nil
                ? "Their level and notes will be preserved."
                : "Their saved build, level, and equipment plan will be preserved."
            pendingRosterStatusChange = PendingRosterStatusChange(
                memberID: member.id,
                memberName: member.name,
                target: status,
                message: "\(impact) \(plan) Story outcomes and rewards remain separate confirmations."
            )
            return false
        }
        guard run.applyRosterStatus(status, memberID: member.id) else {
            errorMessage = status == .active
                ? "Active party is full. Send someone to camp first."
                : "Could not update \(member.name)'s roster status."
            return false
        }
        persistRun()
        Task { await refreshReadiness() }
        return true
    }

    func confirmRosterStatusChange() {
        guard let pending = pendingRosterStatusChange,
              let member = roster.first(where: { $0.id == pending.memberID }) else {
            pendingRosterStatusChange = nil
            return
        }
        pendingRosterStatusChange = nil
        _ = setRosterStatus(pending.target, for: member, confirmed: true)
    }

    func cancelRosterStatusChange() {
        pendingRosterStatusChange = nil
    }

    func gearIsEquipped(_ gear: BuildGear, by member: PartyMember) -> Bool {
        run.equippedByMember?[member.id]?.contains(gear.itemKey) == true
    }

    func gearOwner(_ gear: BuildGear) -> PartyMember? {
        guard let ownerID = run.equipmentOwnerID(for: gear.itemKey) else { return nil }
        return roster.first(where: { $0.id == ownerID })
    }

    func toggleGear(_ gear: BuildGear, for member: PartyMember) {
        guard gear.isMapObjective, run.toggleEquipment(itemKey: gear.itemKey, for: member.id) else { return }
        persistRun()
    }

    func setStoryOutcome(_ outcome: String, confirmed: Bool) {
        run.setStoryOutcome(outcome, confirmed: confirmed)
        persistRun()
    }

    func setIncludeCampPlans(_ enabled: Bool) {
        run.includeCampPlans = enabled
        persistRun()
    }

    func setAllPartyLevels(_ level: Int) {
        guard var members = run.roster else { return }
        members = members.map { member in
            var copy = member
            guard copy.rosterStatus == .active else { return copy }
            copy.level = level
            if let buildId = copy.buildId,
               let build = builds.first(where: { $0.id == buildId }),
               let plan = build.levels.last(where: { $0.level <= level }) {
                copy.className = plan.take
            }
            return copy
        }
        run.roster = members
        run.syncActivePartyProjection()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        Task { await refreshReadiness() }
    }

    func setSelectedAct(_ act: Int) {
        guard (1...3).contains(act) else { return }
        run.selectedAct = act
        persistRun()
    }

    private func syncRegionToRecommendation() {
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

    func requestScreenRecordingPermission() {
        // Keep the synchronous system request in this button's event handler.
        // The tested startup request did not create a manageable TCC row; this
        // path guarantees explicit consent and never prompts from a timer.
        permissionRequestAttemptedThisLaunch = true
        permissionProbeAfterSettings = true
        showScreenRecordingPermissionPrompt = false
        screenRecordingStatus = "Waiting for macOS permission…"
        let requestGranted = PermissionManager.requestScreenRecordingPermission()
        screenCaptureRequestStatus = requestGranted
            ? "Request returned granted"
            : "Choose Open System Settings in the macOS dialog"
        // On current Tahoe builds the legacy request can return false without
        // presenting anything. One pixel request from this explicit user action
        // opens the system-owned flow. The authorization state machine remains
        // in `.wait` afterward, so the map timer cannot repeat this probe.
        Task {
            updateCapturePreflight(PermissionManager.hasScreenRecordingPermission)
            let verified = await PermissionManager.verifyScreenRecordingAccess()
            if verified { permissionProbeAfterSettings = false }
            applyCaptureAuthorization(verified, verifiedByPixels: verified)
            if !verified {
                screenCaptureRequestStatus = "Choose Open System Settings in the macOS dialog"
            }
        }
    }

    private func handlePermissionReturn(_ activatedApp: NSRunningApplication?) async {
        // Opening the privacy pane is not the grant. Wait until the player
        // leaves System Settings, then perform exactly one real pixel probe.
        if permissionProbeAfterSettings {
            if activatedApp?.bundleIdentifier == "com.apple.systempreferences" { return }
            permissionProbeAfterSettings = false
            updateCapturePreflight(PermissionManager.hasScreenRecordingPermission)
            let verified = await PermissionManager.verifyScreenRecordingAccess()
            applyCaptureAuthorization(verified, verifiedByPixels: verified)
            screenCaptureRequestStatus = verified
                ? "Granted • pixel capture verified"
                : "Not granted • retry and choose Open System Settings"
            return
        }
        // App activation is frequent while playing. With automatic capture
        // disabled it must not turn a harmless status refresh into a pixel
        // probe merely because Screen Recording was granted in the past.
        guard automaticCaptureEnabled else {
            updateCapturePreflight(PermissionManager.hasScreenRecordingPermission)
            screenRecordingStatus = PermissionManager.hasScreenRecordingPermission
                ? "Granted by macOS • monitoring off"
                : "Optional • monitoring off"
            screenCaptureVerificationStatus = "Not checked • monitoring off"
            return
        }
        await refreshCaptureAuthorization(force: true, promptIfMissing: false)
    }

    func openScreenRecordingSettings() { PermissionManager.openScreenRecordingSettings() }

    func testCapture() async {
        guard await prepareCaptureForUserAction() else { return }
        do {
            let screenshot = try await captureBG3(markStatus: "Allowed by BG3 capture test")
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            statusMessage = "BG3 window capture verified"
            errorMessage = nil
        } catch { }
    }

    func checkScreen() async {
        guard !isLoading, let checkpoint = currentCheckpoint else { return }
        guard await prepareCaptureForUserAction() else { return }
        isLoading = true
        errorMessage = nil
        do {
            let screenshot = try await captureBG3(markStatus: "Allowed by successful capture")
            let capturedAt = Date()
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            let context = BackendContext(
                gameDetected: gameDetected,
                gameName: gameName,
                checkpointId: checkpoint.id,
                party: activeParty,
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height
            )
            let response = try await backendClient.analyze(imageData: screenshot.data, context: context)
            latestResponse = response
            latestLatencyMs = response.latencyMs
            statusMessage = response.ok ? "Screen read — tap a suggestion to jump there" : "Screen analysis unavailable"
            if response.ok { recordVisualMemory(response, capturedAt: capturedAt) }
            else { errorMessage = response.error }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func confirmScreenCandidate(_ candidate: ScreenCandidate) {
        guard let checkpoint = route.first(where: { $0.id == candidate.checkpointId }) else { return }
        selectCheckpoint(checkpoint)
        latestResponse = nil
    }

    func reviewVisualCompletion(_ candidate: VisualCompletionCandidate) {
        guard let step = walkthrough.first(where: { $0.id == candidate.stepId }),
              walkthroughDisposition(step) == .pending else { return }
        focusWalkthroughStep(step)
        statusMessage = "Vision evidence only • review and confirm Done"
        overlayExpanded = true
        syncOverlay()
    }

    func sendChat(_ quickPrompt: String? = nil) async {
        // Dialogue/exploration focus may not have its own fight checkpoint;
        // ground chat in the focused walkthrough step plus the next reviewed
        // checkpoint rather than making Ask silently do nothing.
        guard let checkpoint = currentCheckpoint ?? recommendedCheckpoint else { return }
        let message = quickPrompt ?? chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatDraft = ""
        chatLines.append(ChatLine(role: "You", text: message))

        do {
            let response = try await backendClient.chat(ChatRequest(
                message: message,
                checkpointId: checkpoint.id,
                party: activeParty,
                completedCheckpointIds: completedIds,
                walkthroughStepId: currentWalkthroughStep?.id,
                screenshotContext: latestResponse?.screenSummary ?? latestVisualMemory?.summary,
                imageBase64: nil,
                screenshotTimestamp: latestVisualMemory?.capturedAt.timeIntervalSince1970,
                context: chatContextSnapshot
            ))
            chatLines.append(ChatLine(role: "Assistant", text: response.answer))
        } catch {
            chatLines.append(ChatLine(role: "Assistant", text: "Chat is offline right now (\(error.localizedDescription))."))
        }
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

    private func refreshReadiness() async {
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
        detectedWindowFrame = detection.windowFrame
        if gameWindowFrame != detection.windowFrame { gameWindowFrame = detection.windowFrame }
        // Capture authorization is owned by refreshCaptureAuthorization (the map
        // loop), not this status loop, so both agree on one source of truth.
        backendHealthy = await backendClient.health()
        backendStatus = backendHealthy ? "OK" : (backendProcess.isRunning ? "Process running, /health offline" : "Offline")
        if !backendHealthy { await startBackend() }
        if telemetryEnabled && backendHealthy {
            telemetryStatus = try? await backendClient.telemetry()
        } else if !telemetryEnabled || !backendHealthy {
            telemetryStatus = nil
        }
        await loadRouteIfNeeded()
        syncOverlay()
        if !gameDetected { isMapOpen = false; mapOverlayController.hide() }
    }

    private func sampleAutomaticScreen(force: Bool = false) async {
        guard automaticCaptureEnabled else { return }
        guard force || Date().timeIntervalSince(lastAutomaticCaptureAt) >= 29 else { return }
        guard !automaticCaptureInFlight else { return }
        automaticCaptureInFlight = true
        defer { automaticCaptureInFlight = false }
        guard gameDetected else {
            if visualMemoryEnabled { visualMemoryStatus = "Waiting for BG3" }
            if mapOverlayCaptureEnabled { mapDetectionStatus = "Waiting for BG3" }
            return
        }
        lastAutomaticCaptureAt = Date()
        // Timer-owned checks never prompt. Enabling either feature explicitly
        // owns the consent flow; subsequent 30-second samples only use a grant.
        await refreshCaptureAuthorization()
        guard captureAuthorized || screenCaptureVerifiedThisLaunch else {
            if visualMemoryEnabled { visualMemoryStatus = "Grant Screen Recording, then return to BG3" }
            if mapOverlayCaptureEnabled { mapDetectionStatus = "Grant Screen Recording, then return to BG3" }
            return
        }
        do {
            let screenshot = try await captureService.captureBG3Window()
            let capturedAt = Date()
            latestLocalDetectionTimestamp = Date().timeIntervalSince1970
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            markScreenCaptureAllowed(status: "Granted • capture active", verifiedByCapture: true)

            if mapOverlayCaptureEnabled {
                await updateMapAlignment(from: screenshot)
            }

            if visualMemoryEnabled {
                guard backendHealthy else {
                    visualMemoryStatus = "Backend unavailable"
                    return
                }
                let context = BackendContext(
                    gameDetected: gameDetected,
                    gameName: gameName,
                    checkpointId: currentCheckpoint?.id,
                    party: activeParty,
                    screenshotWidth: screenshot.width,
                    screenshotHeight: screenshot.height
                )
                let response = try await backendClient.analyze(imageData: screenshot.data, context: context)
                latestResponse = response
                latestLatencyMs = response.latencyMs
                if response.ok {
                    recordVisualMemory(response, capturedAt: capturedAt)
                } else {
                    visualMemoryStatus = response.error ?? "Vision analysis unavailable"
                }
            }
        } catch {
            await handleScreenCaptureFailure(error, showError: false)
            if visualMemoryEnabled { visualMemoryStatus = "Paused • \(error.localizedDescription)" }
            if mapOverlayCaptureEnabled { mapDetectionStatus = "Paused • \(error.localizedDescription)" }
            mapOverlayController.hide()
        }
    }

    private func recordVisualMemory(_ response: AnalysisResponse, capturedAt: Date) {
        let entry = VisualMemoryEntry(
            id: response.analysisId,
            capturedAt: capturedAt,
            summary: response.screenSummary,
            likelyArea: response.detected.likelyArea,
            screenKind: response.detected.screenKind,
            evidence: response.detected.evidence,
            candidates: response.candidates,
            completionCandidates: response.completionCandidates ?? [],
            confidence: response.confidence
        )
        run.visualMemory = VisualMemoryLedger.recording(entry, in: run.visualMemory ?? [])
        visualMemoryStatus = "Remembered \(entry.screenKind) • \(entry.likelyArea)"
        persistRun()
    }

    private func updateMapAlignment(from screenshot: ScreenshotResult) async {
        let context = MapAlignContext(
            checkpointId: currentCheckpoint?.id,
            completedCheckpointIds: completedIds,
            useActiveMarkerSync: true
        )
        if backendHealthy,
           let alignment = try? await backendClient.alignMap(imageData: screenshot.data, context: context),
           alignment.ok {
            isMapOpen = alignment.mapOpen
            mapDetectionConfidence = alignment.confidence
            if alignment.mapOpen {
                mapDetectionStatus = "Overlay locked on (\(alignment.inliers) anchors)"
                updateAlignedMapOverlay(alignment.targets, screenshot: screenshot)
            } else {
                mapDetectionStatus = "No map on screen"
                mapOverlayController.hide()
            }
            return
        }
        let textResult = await mapDetector.detect(jpegData: screenshot.data)
        isMapOpen = textResult.isOpen
        mapDetectionConfidence = textResult.confidence
        mapDetectionStatus = textResult.isOpen ? "Map found — start the backend to see markers" : "No map on screen"
        mapOverlayController.hide()
    }

    private func updateAlignedMapOverlay(_ targets: [MapAlignTarget], screenshot: ScreenshotResult) {
        guard let frame = detectedWindowFrame else { mapOverlayController.hide(); return }
        // Screenshot pixels and the SwiftUI overlay share a top-left origin with
        // y growing downward, so the mapping is a pure scale — no vertical flip.
        let visible = targets.filter(\.onScreen).map { target in
            ScreenMarker(
                id: target.id,
                label: target.label,
                point: CGPoint(
                    x: target.x / Double(screenshot.width) * frame.width,
                    y: target.y / Double(screenshot.height) * frame.height
                ),
                danger: target.danger
            )
        }
        mapOverlayController.show(frame: frame, markers: visible)
    }

    private func persistRun() {
        do { try runStore.save(run) }
        catch { errorMessage = "Could not save run: \(error.localizedDescription)" }
    }

    private func persistSettings() {
        let settings = AssistantSettings(
            telemetryEnabled: telemetryEnabled,
            visualMemoryEnabled: visualMemoryEnabled,
            mapOverlayCaptureEnabled: mapOverlayCaptureEnabled,
            overlayDensity: overlayDensity.rawValue
        )
        do { try runStore.saveSettings(settings) }
        catch { errorMessage = "Could not save settings: \(error.localizedDescription)" }
    }

    private func syncOverlay() {
        if showOverlay && (gameDetected || forceOverlay) { overlayController.show(appState: self, gameFrame: gameWindowFrame) }
        else { overlayController.hide() }
    }

    private func captureBG3(markStatus: String) async throws -> ScreenshotResult {
        do {
            let screenshot = try await captureService.captureBG3Window()
            markScreenCaptureAllowed(status: markStatus, verifiedByCapture: true)
            return screenshot
        } catch { await handleScreenCaptureFailure(error); throw error }
    }

    private func markScreenCaptureAllowed(status: String, verifiedByCapture: Bool) {
        let priorCaptureError = screenCaptureLastError
        captureAuthorized = true
        screenRecordingAllowed = true
        screenRecordingStatus = status
        shouldShowScreenRecordingHelp = false
        screenCaptureLastError = nil
        if errorMessage == priorCaptureError { errorMessage = nil }
        if verifiedByCapture {
            screenCaptureVerifiedThisLaunch = true
            screenCaptureVerificationStatus = "Verified this launch"
        }
    }

    private func handleScreenCaptureFailure(_ error: Error, showError: Bool = true) async {
        let noVisibleWindow = (error as? BG3AssistantError) == .bg3WindowNotFound
        screenCaptureLastError = error.localizedDescription
        if noVisibleWindow, captureAuthorized || screenCaptureVerifiedThisLaunch {
            screenRecordingStatus = "Granted • waiting for BG3"
            screenCaptureVerificationStatus = "Pixel access verified"
            shouldShowScreenRecordingHelp = false
        } else {
            // Stream startup can report a generic audio/video failure for TCC
            // denial. Clear the latch and reconcile with the real pixel probe.
            captureAuthorized = false
            screenCaptureVerifiedThisLaunch = false
            await refreshCaptureAuthorization(force: true, promptIfMissing: false)
            if captureAuthorized {
                screenRecordingStatus = noVisibleWindow ? "Granted • waiting for BG3" : "Granted • BG3 capture unavailable"
                screenCaptureVerificationStatus = "Pixel access verified"
            }
        }
        if showError { errorMessage = error.localizedDescription }
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
