import AppKit
import Foundation

struct ChatLine: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var gameDetected = false
    @Published var gameName = "Not detected"
    @Published var gameDetectionDetail = "Not checked yet"
    @Published var backendHealthy = false
    @Published var backendStatus = "Not checked yet"
    @Published var showOverlay = true { didSet { syncOverlay() } }
    @Published var forceOverlay = false { didSet { syncOverlay() } }
    @Published var overlayExpanded = false { didSet { syncOverlay() } }
    @Published var plannerTab: PlannerTab = .current { didSet { if overlayExpanded { syncOverlay() } } }
    @Published var route: [RouteCheckpoint] = []
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
    @Published var mapDetectionStatus = "Waiting for BG3 window capture"
    @Published var mapDetectionConfidence = 0.0
    @Published var chatDraft = ""
    @Published var chatLines: [ChatLine] = []
    @Published var skipNoteDraft = ""
    @Published var pendingDisposition: CheckpointDisposition?
    @Published var confirmationMessage: String?
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
    @Published var appPermissionIdentity = PermissionManager.appIdentityDescription

    private let detector = BG3Detector()
    private let backendClient = BackendClient()
    private let backendProcess = BackendProcessManager()
    private let captureService = ScreenCaptureService()
    private let mapDetector = MapOpenDetector()
    private let runStore = RunStore()
    private let overlayController = OverlayPanelController()
    private let mapOverlayController = MapMarkerOverlayPanelController()
    private var pollTask: Task<Void, Never>?
    private var mapTask: Task<Void, Never>?
    private var detectedWindowFrame: CGRect?
    @Published private(set) var gameWindowFrame: CGRect?

    // Screen-recording authorization is latched once confirmed so we stop
    // probing (and never risk re-prompting) for the rest of the session.
    private var captureAuthorized = false
    // Set when a capture actually threw a TCC denial. From then on the preflight
    // is treated as unreliable (it can report a stale grant for an old code
    // signature after a rebuild) and only a live probe/capture can re-authorize.
    private var captureDeniedObserved = false
    private var lastCaptureProbe = Date.distantPast
    private var activationObserver: Any?

    init() {
        var loaded = runStore.load()
        loaded.migrateLegacyPartySlots()
        run = loaded
    }

    var completedIds: [String] {
        run.progress.compactMap { $0.value.disposition == .completed ? $0.key : nil }
    }

    var currentCheckpoint: RouteCheckpoint? {
        RunSafety.nextCheckpoint(route: route, progress: run.progress, selectedId: run.selectedCheckpointId, partyLevel: lowestPartyLevel)
    }

    var currentProgress: CheckpointProgress {
        guard let id = currentCheckpoint?.id else { return CheckpointProgress() }
        return run.progress[id] ?? CheckpointProgress()
    }

    var lowestPartyLevel: Int { run.party.map(\.level).min() ?? 1 }
    var selectedAct: Int { run.selectedAct ?? 1 }
    var levelActivityPlan: LevelActivityPlan? {
        RunSafety.activityPlan(
            route: route,
            progress: run.progress,
            selectedId: run.selectedCheckpointId,
            partyLevel: lowestPartyLevel
        )
    }
    var routeRecommendationReason: String? {
        guard let checkpoint = currentCheckpoint else { return nil }
        if run.selectedCheckpointId != nil { return "Pinned by you • \(RunSafety.routePhaseName(checkpoint))" }
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
        return RunSafety.actTwoBlockers(route: route, progress: run.progress)
    }

    func start() async {
        guard pollTask == nil else { return }
        // The user typically grants access in System Settings and then returns
        // to BG3 (not this window), so app-activation alone is not enough — but
        // it is the fastest signal when they do come back here.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshCaptureAuthorization(force: true) }
        }
        await refreshCaptureAuthorization(force: true)
        await refreshStatuses()
        await loadRouteIfNeeded()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatuses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        mapTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleMapState()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        mapTask?.cancel()
        pollTask = nil
        mapTask = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        overlayController.hide()
        mapOverlayController.hide()
        backendProcess.stop()
    }

    /// Resolve screen-recording access from the authoritative source, working
    /// around the preflight's process-lifetime false cache. Latches once granted
    /// so we never re-probe (and never risk re-prompting) afterwards.
    func refreshCaptureAuthorization(force: Bool = false) async {
        if captureAuthorized || screenCaptureVerifiedThisLaunch {
            applyCaptureAuthorization(true)
            return
        }
        // Trust the fast preflight only until a real capture proves it wrong;
        // after a denial, the live probe is the sole source of truth.
        if !captureDeniedObserved, PermissionManager.hasScreenRecordingPermission {
            applyCaptureAuthorization(true)
            return
        }
        guard force || Date().timeIntervalSince(lastCaptureProbe) > 4 else { return }
        lastCaptureProbe = Date()
        applyCaptureAuthorization(await PermissionManager.probeCaptureAccess())
    }

    private func applyCaptureAuthorization(_ authorized: Bool) {
        if authorized { captureAuthorized = true }
        screenRecordingAllowed = authorized
        screenRecordingPreflightAllowed = authorized
        screenRecordingPreflightStatus = authorized ? "Granted by macOS" : "Not granted by macOS"
        if authorized {
            screenRecordingStatus = screenCaptureVerifiedThisLaunch ? "Granted • capture active" : "Granted by macOS"
            if !screenCaptureVerifiedThisLaunch { screenCaptureVerificationStatus = "Granted • verifying capture" }
            shouldShowScreenRecordingHelp = false
        } else {
            screenRecordingStatus = "Not granted by macOS"
            screenCaptureVerificationStatus = "Waiting for permission"
            shouldShowScreenRecordingHelp = true
        }
    }

    func launchBG3() {
        guard let url = URL(string: "steam://run/1086940") else { return }
        NSWorkspace.shared.open(url)
    }

    func openActOneMap(buildId: String? = nil, item: String? = nil, level: Int? = nil) {
        Task {
            if !backendHealthy { await startBackend() }
            var components = URLComponents(string: "http://127.0.0.1:8787/map")
            let partyBuilds = run.party.compactMap(\.buildId)
            var query: [URLQueryItem] = [
                URLQueryItem(name: "act", value: String(selectedAct)),
                URLQueryItem(name: "level", value: String(level ?? lowestPartyLevel)),
                URLQueryItem(name: "builds", value: partyBuilds.joined(separator: ",")),
                URLQueryItem(name: "done", value: completedIds.joined(separator: ",")),
            ]
            if let partyData = try? JSONEncoder().encode(run.party),
               let partyJSON = String(data: partyData, encoding: .utf8) {
                query.append(URLQueryItem(name: "party", value: partyJSON))
            }
            if let buildId { query.append(URLQueryItem(name: "build", value: buildId)) }
            if let item {
                query.append(URLQueryItem(name: "item", value: item))
                query.append(URLQueryItem(name: "tab", value: "route"))
            } else if buildId != nil {
                query.append(URLQueryItem(name: "tab", value: "party"))
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
        plannerTab = .party
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

    func hideAssistantOverlay() {
        forceOverlay = false
        showOverlay = false
    }

    func selectCheckpoint(_ checkpoint: RouteCheckpoint) {
        run.selectedCheckpointId = checkpoint.id
        run.mapRegion = checkpoint.region
        persistRun()
        skipNoteDraft = run.progress[checkpoint.id]?.skipNote ?? ""
        combatCardPinned = false
        plannerTab = .current
        Task { await refreshReadiness() }
    }

    func followRecommendedRoute() {
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        Task { await refreshReadiness() }
    }

    func setDisposition(_ disposition: CheckpointDisposition, note: String = "") {
        guard let checkpoint = currentCheckpoint else { return }
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        progress.disposition = disposition
        progress.skipNote = note
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        if disposition != .pending {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        combatCardPinned = false
        persistRun()
        Task { await refreshReadiness() }
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
        fresh.guideVersion = availableGuideVersion
        run = fresh
        skipNoteDraft = ""
        combatCardPinned = false
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
        guard let index = run.party.firstIndex(where: { $0.id == member.id }) else { return }
        run.party[index] = member
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        Task { await refreshReadiness() }
    }

    func setAllPartyLevels(_ level: Int) {
        run.party = run.party.map { member in
            var copy = member
            copy.level = level
            if let buildId = copy.buildId,
               let build = builds.first(where: { $0.id == buildId }),
               let plan = build.levels.last(where: { $0.level <= level }) {
                copy.className = plan.take
            }
            return copy
        }
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        Task { await refreshReadiness() }
    }

    func setSelectedAct(_ act: Int) {
        guard (1...3).contains(act) else { return }
        run.selectedAct = act
        persistRun()
    }

    private func syncRegionToRecommendation() {
        guard let checkpoint = RunSafety.nextCheckpoint(
            route: route,
            progress: run.progress,
            selectedId: nil,
            partyLevel: lowestPartyLevel
        ) else { return }
        run.mapRegion = checkpoint.region
    }

    func requestScreenRecordingPermission() {
        PermissionManager.requestScreenRecordingPermission()
        // The modal's return value lags the grant; confirm with a forced probe.
        Task { await refreshCaptureAuthorization(force: true) }
    }

    func openScreenRecordingSettings() { PermissionManager.openScreenRecordingSettings() }

    func testCapture() async {
        do {
            let screenshot = try await captureBG3(markStatus: "Allowed by BG3 capture test")
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            statusMessage = "BG3 window capture verified"
            errorMessage = nil
        } catch { handleScreenCaptureFailure(error) }
    }

    func checkScreen() async {
        guard !isLoading, let checkpoint = currentCheckpoint else { return }
        isLoading = true
        errorMessage = nil
        do {
            let screenshot = try await captureBG3(markStatus: "Allowed by successful capture")
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            let context = BackendContext(
                gameDetected: gameDetected,
                gameName: gameName,
                checkpointId: checkpoint.id,
                party: run.party,
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height
            )
            let response = try await backendClient.analyze(imageData: screenshot.data, context: context)
            latestResponse = response
            latestLatencyMs = response.latencyMs
            statusMessage = response.ok ? "Screen read — tap a suggestion to jump there" : "Screen analysis unavailable"
            if !response.ok { errorMessage = response.error }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func confirmScreenCandidate(_ candidate: ScreenCandidate) {
        guard let checkpoint = route.first(where: { $0.id == candidate.checkpointId }) else { return }
        selectCheckpoint(checkpoint)
        latestResponse = nil
    }

    func sendChat(_ quickPrompt: String? = nil) async {
        guard let checkpoint = currentCheckpoint else { return }
        let message = quickPrompt ?? chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatDraft = ""
        chatLines.append(ChatLine(role: "You", text: message))
        do {
            let response = try await backendClient.chat(ChatRequest(
                message: message,
                checkpointId: checkpoint.id,
                party: run.party,
                completedCheckpointIds: completedIds,
                screenshotContext: latestResponse?.screenSummary
            ))
            chatLines.append(ChatLine(role: "Assistant", text: response.answer))
        } catch {
            chatLines.append(ChatLine(role: "Assistant", text: "Unknown: chat backend unavailable (\(error.localizedDescription))."))
        }
    }

    private func loadRouteIfNeeded(force: Bool = false) async {
        guard force || route.isEmpty else { return }
        guard backendHealthy else { return }
        do {
            let payload = try await backendClient.route()
            route = payload.checkpoints
            builds = payload.builds
            availableGuideVersion = payload.guideVersion
            if run.guideVersion.isEmpty { run.guideVersion = payload.guideVersion }
            statusMessage = "Act 1 guide ready"
            persistRun()
            await refreshReadiness()
        } catch { errorMessage = "Could not load Act 1 route: \(error.localizedDescription)" }
    }

    private func refreshReadiness() async {
        guard backendHealthy, let checkpoint = currentCheckpoint else { readiness = nil; return }
        do {
            readiness = try await backendClient.readiness(ReadinessRequest(
                checkpointId: checkpoint.id,
                party: run.party,
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
        await loadRouteIfNeeded()
        syncOverlay()
        if !gameDetected { isMapOpen = false; mapOverlayController.hide() }
    }

    private func sampleMapState() async {
        guard gameDetected else {
            mapDetectionStatus = "Waiting for BG3"
            return
        }
        // Re-probe (throttled) so a grant made after launch is picked up within
        // one tick, even though the user granted it from System Settings while
        // BG3 — not this app — was frontmost. No involuntary capture is attempted
        // until authorization is confirmed, so the system prompt never repeats.
        await refreshCaptureAuthorization()
        guard captureAuthorized || screenCaptureVerifiedThisLaunch else {
            mapDetectionStatus = "Grant Screen Recording, then return to the game"
            return
        }
        do {
            let screenshot = try await captureService.captureBG3Window()
            markScreenCaptureAllowed(status: "Granted • capture active", verifiedByCapture: true)
            // Feature alignment is authoritative in both directions when it ran:
            // a geometric match proves the map screen is open at that pan/zoom,
            // and its absence on a valid response proves it is not. Regions not
            // on the Wilderness tileset (Nautiloid, Crèche) simply never match,
            // so no overlay is drawn there — honest silence over guesses.
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
            // Backend unavailable: OCR still reports whether the map is open,
            // but without a verified transform no markers are drawn.
            let textResult = await mapDetector.detect(jpegData: screenshot.data)
            isMapOpen = textResult.isOpen
            mapDetectionConfidence = textResult.confidence
            mapDetectionStatus = textResult.isOpen ? "Map found — start the backend to see markers" : "No map on screen"
            mapOverlayController.hide()
        } catch {
            handleScreenCaptureFailure(error, showError: false)
            mapDetectionStatus = "Map detector paused: \(error.localizedDescription)"
            mapOverlayController.hide()
        }
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

    private func syncOverlay() {
        if showOverlay && (gameDetected || forceOverlay) { overlayController.show(appState: self, gameFrame: gameWindowFrame) }
        else { overlayController.hide() }
    }

    private func captureBG3(markStatus: String) async throws -> ScreenshotResult {
        do {
            let screenshot = try await captureService.captureBG3Window()
            markScreenCaptureAllowed(status: markStatus, verifiedByCapture: true)
            return screenshot
        } catch { handleScreenCaptureFailure(error); throw error }
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

    private func handleScreenCaptureFailure(_ error: Error, showError: Bool = true) {
        // A TCC denial from the capture API is authoritative — it overrides any
        // stale "granted" latch or preflight (e.g. after a rebuild changed the
        // code signature). Drop authorization so the app shows the grant prompt
        // and self-heals once the user re-grants to this build.
        if PermissionManager.isPermissionDenied(error) {
            captureDeniedObserved = true
            captureAuthorized = false
            screenCaptureVerifiedThisLaunch = false
        }
        let noVisibleWindow = (error as? BG3AssistantError) == .bg3WindowNotFound
        let permissionFailure = PermissionManager.isPermissionDenied(error)
            || (!captureAuthorized && !screenCaptureVerifiedThisLaunch && !PermissionManager.hasScreenRecordingPermission)
        screenRecordingAllowed = !permissionFailure
        screenRecordingStatus = permissionFailure ? "Not granted by macOS" : (noVisibleWindow ? "Granted by macOS" : "Granted • capture unavailable")
        shouldShowScreenRecordingHelp = permissionFailure
        screenCaptureLastError = error.localizedDescription
        screenCaptureVerificationStatus = permissionFailure ? "Waiting for permission" : (noVisibleWindow ? "Waiting for BG3 window" : "Capture failed")
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
