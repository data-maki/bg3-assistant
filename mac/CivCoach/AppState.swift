import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var civDetected = false
    @Published var civName = "Not detected"
    @Published var civDetectionDetail = "Not checked yet"
    @Published var backendHealthy = false
    @Published var backendStatus = "Not checked yet"
    @Published var showOverlay = true {
        didSet { syncOverlay() }
    }
    @Published var forceOverlay = false {
        didSet { syncOverlay() }
    }
    @Published var isLoading = false
    @Published var overlayExpanded = false
    @Published var screenRecordingAllowed = PermissionManager.hasScreenRecordingPermission
    @Published var screenRecordingStatus = PermissionManager.hasScreenRecordingPermission ? "Allowed" : "Not verified"
    @Published var shouldShowScreenRecordingHelp = false
    @Published var screenCaptureLastError: String?
    @Published var appPermissionIdentity = PermissionManager.appIdentityDescription
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var latestScreenshotSize = "none"
    @Published var latestScreenshotPath = "none"
    @Published var latestLatencyMs = 0
    @Published var latestResponse: AnalysisResponse?
    @Published var isRecording = false
    @Published var recordingStatus = "Not recording"
    @Published var currentGameLogPath = "none"
    @Published var turnLogEntries: [GameLogEntry] = []
    @Published var autoRecordTurns = true
    @Published var turnLogOverlayMinimized = false {
        didSet { syncTurnLogOverlay() }
    }
    @Published var showTurnLogOverlay = true {
        didSet { syncTurnLogOverlay() }
    }

    private let detector = CivDetector()
    private let backendClient = BackendClient()
    private let backendProcess = BackendProcessManager()
    private let captureService = ScreenCaptureService()
    private let audioPlayback = AudioPlaybackService()
    private let debugLogger = Logger()
    private let gameLogManager = GameLogManager()
    private let overlayController = OverlayPanelController()
    private let turnLogOverlayController = TurnLogOverlayPanelController()
    private var pollTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var previousObservation: ObservationContext?
    private var userStoppedRecording = false

    func start() async {
        guard pollTask == nil else { return }
        await refreshStatuses()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatuses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func launchCiv() {
        guard let url = URL(string: "steam://run/1295660") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestScreenRecordingPermission() {
        let allowed = PermissionManager.requestScreenRecordingPermission()
        appPermissionIdentity = PermissionManager.appIdentityDescription
        if allowed {
            markScreenCaptureAllowed(status: "Allowed")
        } else {
            screenRecordingAllowed = false
            screenRecordingStatus = "Not verified"
        }
        Task { await refreshScreenCaptureStatus() }
    }

    func openScreenRecordingSettings() {
        PermissionManager.openScreenRecordingSettings()
    }

    func startBackend() async {
        backendStatus = "Starting backend..."
        do {
            try backendProcess.startIfNeeded()
            for _ in 0..<20 {
                if await backendClient.health() {
                    backendHealthy = true
                    backendStatus = "OK"
                    errorMessage = nil
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            backendHealthy = false
            backendStatus = "Started process, waiting for /health"
        } catch {
            backendHealthy = false
            backendStatus = "Start failed"
            errorMessage = error.localizedDescription
        }
    }

    func showOverlayNow() {
        forceOverlay = true
        showOverlay = true
        overlayController.show(appState: self)
    }

    func toggleRecording() async {
        if isRecording {
            userStoppedRecording = true
            stopRecording()
        } else {
            userStoppedRecording = false
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        do {
            await refreshScreenCaptureStatus()
            if !backendHealthy {
                await startBackend()
            }
            let logURL = try gameLogManager.startNewGameLog(initialDetection: civName)
            currentGameLogPath = logURL.path
            turnLogEntries = []
            previousObservation = nil
            isRecording = true
            recordingStatus = "Recording every 10 seconds"
            showTurnLogOverlay = true
            syncTurnLogOverlay()
            recordingTask = Task { [weak self] in
                while self?.isRecording == true {
                    await self?.recordObservation()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            recordingStatus = "Recording failed"
            syncTurnLogOverlay()
        }
    }

    func stopRecording() {
        isRecording = false
        recordingTask?.cancel()
        recordingTask = nil
        recordingStatus = "Stopped"
        syncTurnLogOverlay()
    }

    func toggleTurnLogOverlay() {
        turnLogOverlayMinimized.toggle()
    }

    func testCapture() async {
        do {
            let screenshot = try await captureScreen(markStatus: "Allowed by capture test")
            let path = try debugLogger.saveScreenshot(screenshot.data)
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            latestScreenshotPath = path.path
            statusMessage = "Captured test screenshot"
            errorMessage = nil
        } catch {
            handleScreenCaptureFailure(error)
        }
    }

    func ask() async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "Reading screen..."
        errorMessage = nil
        overlayController.hide()

        do {
            try await Task.sleep(for: .milliseconds(250))
            let screenshot = try await captureScreen(markStatus: "Allowed by successful capture")
            let screenshotPath = try debugLogger.saveScreenshot(screenshot.data)
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            latestScreenshotPath = screenshotPath.path

            let context = BackendContext(
                app: "CivCoach",
                gameDetected: civDetected,
                gameName: civName,
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height
            )
            let response = try await backendClient.analyze(imageData: screenshot.data, context: context)
            latestResponse = response
            latestLatencyMs = response.latencyMs
            try debugLogger.saveResponse(response)

            if response.ok {
                statusMessage = "Analysis complete"
                overlayExpanded = true
                if !response.audioBase64.isEmpty {
                    try audioPlayback.play(base64MP3: response.audioBase64)
                }
            } else {
                errorMessage = response.error ?? "Backend analysis failed"
                statusMessage = "Analysis failed"
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Analysis failed"
        }

        isLoading = false
        syncOverlay()
    }

    private func recordObservation() async {
        guard isRecording else { return }
        recordingStatus = "Capturing observation..."
        do {
            if !backendHealthy {
                await startBackend()
            }

            let screenshot = try await captureScreen(markStatus: "Allowed by successful capture")
            let screenshotPath = try debugLogger.saveScreenshot(screenshot.data)
            latestScreenshotSize = "\(screenshot.width)x\(screenshot.height)"
            latestScreenshotPath = screenshotPath.path

            let context = BackendContext(
                app: "CivCoach",
                gameDetected: civDetected,
                gameName: civName,
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height,
                mode: "recording",
                skipTTS: true,
                gameLogId: gameLogManager.gameId,
                previousObservation: previousObservation
            )
            let response = try await backendClient.analyze(imageData: screenshot.data, context: context)
            latestResponse = response
            latestLatencyMs = response.latencyMs
            try debugLogger.saveResponse(response)

            if response.ok {
                let entry = GameLogEntry(
                    timestamp: Date(),
                    turnNumber: response.observation.turnNumber,
                    year: response.observation.year,
                    action: response.observation.actionCandidate,
                    actionKind: response.observation.actionKind,
                    confidence: response.observation.actionConfidence,
                    summary: response.screenSummary,
                    importantValues: response.observation.importantValues,
                    changedValues: response.observation.changedSincePrevious
                )
                turnLogEntries.append(entry)
                if turnLogEntries.count > 40 {
                    turnLogEntries.removeFirst(turnLogEntries.count - 40)
                }
                try gameLogManager.append(entry)
                previousObservation = ObservationContext(
                    turnNumber: response.observation.turnNumber,
                    year: response.observation.year,
                    screenSummary: response.screenSummary,
                    actionCandidate: response.observation.actionCandidate,
                    resources: response.detected.resources,
                    selectedUnitOrPanel: response.detected.selectedUnitOrPanel,
                    currentProblemOrPrompt: response.detected.currentProblemOrPrompt
                )
                recordingStatus = "Last observation logged"
                errorMessage = nil
            } else {
                recordingStatus = "Observation failed"
                errorMessage = response.error ?? "Backend observation failed"
            }
        } catch {
            recordingStatus = "Observation failed"
            errorMessage = error.localizedDescription
        }
        syncTurnLogOverlay()
    }

    func hideOverlay() {
        overlayController.hide()
    }

    private func refreshStatuses() async {
        let detection = detector.detect()
        civDetected = detection.isRunning
        civName = detection.displayName
        civDetectionDetail = detection.detail
        await refreshScreenCaptureStatus()
        backendHealthy = await backendClient.health()
        if backendHealthy {
            backendStatus = "OK"
        } else if backendProcess.isRunning {
            backendStatus = "Process running, /health offline"
        } else {
            backendStatus = "Offline"
            await startBackend()
        }
        if autoRecordTurns && !userStoppedRecording && civDetected && backendHealthy && !isRecording && !shouldShowScreenRecordingHelp {
            await startRecording()
        }
        syncOverlay()
        syncTurnLogOverlay()
    }

    private func syncOverlay() {
        if showOverlay && (civDetected || forceOverlay) {
            overlayController.show(appState: self)
        } else {
            overlayController.hide()
        }
    }

    private func syncTurnLogOverlay() {
        if showTurnLogOverlay && (isRecording || !turnLogEntries.isEmpty || currentGameLogPath != "none") {
            turnLogOverlayController.show(appState: self)
        } else {
            turnLogOverlayController.hide()
        }
    }

    private func refreshScreenCaptureStatus() async {
        let preflightAllowed = PermissionManager.hasScreenRecordingPermission
        appPermissionIdentity = PermissionManager.appIdentityDescription
        if preflightAllowed && !shouldShowScreenRecordingHelp {
            markScreenCaptureAllowed(status: "Allowed")
        } else if !screenRecordingAllowed && !shouldShowScreenRecordingHelp {
            screenRecordingStatus = "Not verified"
        }
    }

    private func captureScreen(markStatus status: String) async throws -> ScreenshotResult {
        do {
            let screenshot = try await captureService.capture()
            markScreenCaptureAllowed(status: status)
            return screenshot
        } catch {
            handleScreenCaptureFailure(error)
            throw error
        }
    }

    private func markScreenCaptureAllowed(status: String) {
        screenRecordingAllowed = true
        screenRecordingStatus = status
        shouldShowScreenRecordingHelp = false
        screenCaptureLastError = nil
        appPermissionIdentity = PermissionManager.appIdentityDescription
    }

    private func handleScreenCaptureFailure(_ error: Error) {
        let permissionFailure = isScreenRecordingPermissionError(error)
        screenRecordingAllowed = false
        screenRecordingStatus = permissionFailure ? "Capture blocked" : "Capture failed"
        shouldShowScreenRecordingHelp = permissionFailure
        screenCaptureLastError = error.localizedDescription
        errorMessage = error.localizedDescription
    }

    private func isScreenRecordingPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let text = "\(nsError.domain) \(nsError.code) \(error.localizedDescription)".lowercased()
        return [
            "tcc",
            "declined",
            "denied",
            "not authorized",
            "not permitted",
            "permission",
            "privacy",
            "screen recording",
            "capture access"
        ].contains { text.contains($0) }
    }
}

enum CivCoachError: LocalizedError {
    case screenRecordingPermissionMissing
    case screenCaptureFailed
    case imageEncodingFailed
    case invalidBackendResponse
    case audioDecodingFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is missing. Open System Settings -> Privacy & Security -> Screen Recording and enable CivCoach."
        case .screenCaptureFailed:
            return "Could not capture the screen."
        case .imageEncodingFailed:
            return "Could not encode the screenshot."
        case .invalidBackendResponse:
            return "The backend returned an invalid response."
        case .audioDecodingFailed:
            return "Could not decode backend audio."
        }
    }
}
