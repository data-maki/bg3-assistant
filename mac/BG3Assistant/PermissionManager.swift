import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum PermissionManager {
    /// Fast, synchronous hint. Reliable when it returns `true`, but macOS caches
    /// a `false` result for the whole process lifetime — so after the user grants
    /// access mid-session it keeps reporting `false`. Never treat a `false` here
    /// as authoritative; confirm with `probeCaptureAccess()`.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The authoritative, non-caching check: can we actually enumerate the
    /// screen right now? Reflects a grant made after launch, which the preflight
    /// cannot. On a genuine first run this triggers the one-time system prompt.
    static func probeCaptureAccess() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    /// Pops the system permission modal. Only ever call this from an explicit
    /// user action — calling it on a timer re-prompts endlessly.
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

    static func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static var appIdentityDescription: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown bundle id"
        let path = Bundle.main.bundleURL.path
        return "\(bundleID) at \(path)"
    }
}
