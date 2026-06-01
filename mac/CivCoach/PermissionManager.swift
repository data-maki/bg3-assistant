import AppKit
import CoreGraphics
import Foundation

enum PermissionManager {
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
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
