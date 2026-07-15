import AppKit
import Foundation

@MainActor
extension AppState {
    func refreshCaptureAuthorization(force: Bool = false, promptIfMissing: Bool = false) async {
        guard !captureAuthorizationRefreshInFlight else { return }
        captureAuthorizationRefreshInFlight = true
        defer { captureAuthorizationRefreshInFlight = false }

        let action = PermissionManager.authorizationAction(
            preflightGranted: PermissionManager.hasScreenRecordingPermission,
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
            lastCaptureProbe = .now
            let verified = await PermissionManager.verifyScreenRecordingAccess()
            applyCaptureAuthorization(verified, verifiedByPixels: verified)
            if !verified, promptIfMissing, !permissionRequestAttemptedThisLaunch {
                showScreenRecordingPermissionPrompt = true
            }
        case .wait:
            applyCaptureAuthorization(false, verifiedByPixels: false)
        }
    }

    func prepareCaptureForUserAction() async -> Bool {
        await refreshCaptureAuthorization(force: true, promptIfMissing: true)
        return captureAuthorized || screenCaptureVerifiedThisLaunch
    }

    func requestScreenRecordingPermission() {
        permissionRequestAttemptedThisLaunch = true
        permissionProbeAfterSettings = true
        showScreenRecordingPermissionPrompt = false
        PermissionManager.requestScreenRecordingPermission()
        Task {
            let verified = await PermissionManager.verifyScreenRecordingAccess()
            if verified { permissionProbeAfterSettings = false }
            applyCaptureAuthorization(verified, verifiedByPixels: verified)
            if verified, plannerTab == .chat { await prepareChatScreenshot() }
        }
    }

    func handlePermissionReturn(_ activatedApp: NSRunningApplication?) async {
        guard permissionProbeAfterSettings else { return }
        if activatedApp?.bundleIdentifier == "com.apple.systempreferences" { return }
        permissionProbeAfterSettings = false
        let verified = await PermissionManager.verifyScreenRecordingAccess()
        applyCaptureAuthorization(verified, verifiedByPixels: verified)
        if verified, plannerTab == .chat { await prepareChatScreenshot() }
    }

    func captureBG3() async throws -> ScreenshotResult {
        do {
            let screenshot = try await captureService.captureBG3Window()
            applyCaptureAuthorization(true, verifiedByPixels: true)
            return screenshot
        } catch {
            if (error as? BG3AssistantError) != .bg3WindowNotFound {
                applyCaptureAuthorization(false, verifiedByPixels: false)
                await refreshCaptureAuthorization(force: true, promptIfMissing: false)
            }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func applyCaptureAuthorization(_ authorized: Bool, verifiedByPixels: Bool) {
        captureAuthorized = authorized
        screenCaptureVerifiedThisLaunch = authorized && verifiedByPixels
    }
}
