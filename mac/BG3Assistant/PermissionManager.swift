import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureAuthorizationAction: Equatable {
    case alreadyVerified
    case offerRequest
    case verifyPixels
    case wait
}

enum PermissionManager {
    /// Fast, synchronous TCC hint. Keep it visible for diagnostics, but do not
    /// claim capture is usable until a real pixel capture succeeds.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func authorizationAction(
        preflightGranted: Bool,
        verifiedThisLaunch: Bool,
        requestAttempted: Bool,
        promptIfMissing: Bool
    ) -> ScreenCaptureAuthorizationAction {
        if verifiedThisLaunch { return .alreadyVerified }
        if preflightGranted { return .verifyPixels }
        // A request that returned false is waiting on the user in System
        // Settings. Do not repeat real capture attempts while that
        // system-owned flow is unresolved.
        if requestAttempted { return .wait }
        return promptIfMissing ? .offerRequest : .wait
    }

    /// ScreenCaptureKit can enumerate displays and windows without usable pixel
    /// access on current macOS releases. A tiny display screenshot is the only
    /// probe used as proof that capture is actually authorized.
    static func verifyScreenRecordingAccess() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 16
            configuration.height = 16
            configuration.queueDepth = 1
            configuration.showsCursor = false
            configuration.capturesAudio = false
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = false
            }
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    /// Registers this signed app with Screen Recording TCC and, when needed,
    /// presents the system prompt. Invoke it directly from the user's consent
    /// action so the request is explicit and never originates from a timer.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// True when a capture error is a Screen Recording TCC denial. This is the
    /// authoritative signal: the preflight can report a stale "granted" for an
    /// old code signature after a rebuild while the capture APIs enforce the new
    /// one and throw this — so the error, not the preflight, must win.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        // SCStreamError.userDeclined
        return nsError.domain == SCStreamError.errorDomain && nsError.code == -3801
    }

}
