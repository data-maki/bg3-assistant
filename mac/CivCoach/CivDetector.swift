import AppKit
import CoreGraphics
import Foundation

struct CivDetection {
    let isRunning: Bool
    let displayName: String
    let detail: String
}

struct CivDetector {
    private let names = [
        "CivilizationVII",
        "Civilization VII",
        "Sid Meier's Civilization VII",
        "Civ VII",
        "Firaxis",
    ]

    func detect() -> CivDetection {
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, matches(name) {
                return CivDetection(isRunning: true, displayName: name, detail: "Matched running app name")
            }
            if let executable = app.executableURL?.lastPathComponent, matches(executable) {
                return CivDetection(isRunning: true, displayName: executable, detail: "Matched executable name")
            }
            if let path = app.executableURL?.path, matches(path) {
                return CivDetection(isRunning: true, displayName: app.localizedName ?? app.executableURL?.lastPathComponent ?? path, detail: "Matched executable path")
            }
            if let bundleID = app.bundleIdentifier, matches(bundleID) {
                return CivDetection(isRunning: true, displayName: app.localizedName ?? bundleID, detail: "Matched bundle identifier")
            }
        }

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return CivDetection(isRunning: false, displayName: "Not detected", detail: "No visible windows returned")
        }

        for window in windows {
            let owner = window[kCGWindowOwnerName as String] as? String
            let title = window[kCGWindowName as String] as? String
            if let owner, matches(owner) {
                return CivDetection(isRunning: true, displayName: owner, detail: "Matched window owner")
            }
            if let title, matches(title) {
                return CivDetection(isRunning: true, displayName: title, detail: "Matched window title")
            }
        }

        return CivDetection(isRunning: false, displayName: "Not detected", detail: "No Civ VII app or window name matched")
    }

    private func matches(_ value: String) -> Bool {
        names.contains { value.localizedCaseInsensitiveContains($0) }
    }
}
