import AppKit
import CoreGraphics
import Foundation

struct BG3Detection {
    let isRunning: Bool
    let displayName: String
    let detail: String
    let windowFrame: CGRect?
}

struct BG3Detector {
    private static let names = ["Baldur's Gate 3", "BaldursGate3", "Baldur's Gate III"]

    static func matchesIdentity(applicationName: String, title: String = "", bundleIdentifier: String = "") -> Bool {
        if bundleIdentifier.localizedCaseInsensitiveCompare("com.larian.bg3") == .orderedSame { return true }
        return names.contains { name in
            applicationName.localizedCaseInsensitiveContains(name) || title.localizedCaseInsensitiveContains(name)
        }
    }

    static func largestFrameIndex(_ frames: [CGRect]) -> Int? {
        frames.indices.max { lhs, rhs in
            frames[lhs].width * frames[lhs].height < frames[rhs].width * frames[rhs].height
        }
    }

    static func capturePixelSize(for frame: CGRect) -> (width: Int, height: Int) {
        (max(1, Int(frame.width)), max(1, Int(frame.height)))
    }

    func detect() -> BG3Detection {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let matchingWindows = windows.filter { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            return Self.matchesIdentity(applicationName: owner, title: title)
        }
        let rawFrames = matchingWindows.map { window -> CGRect in
            guard let dictionary = window[kCGWindowBounds as String] as? [String: NSNumber] else { return .zero }
            return CGRect(
                x: dictionary["X"]?.doubleValue ?? 0,
                y: dictionary["Y"]?.doubleValue ?? 0,
                width: dictionary["Width"]?.doubleValue ?? 0,
                height: dictionary["Height"]?.doubleValue ?? 0
            )
        }
        if let index = Self.largestFrameIndex(rawFrames) {
            let window = matchingWindows[index]
            let raw = rawFrames[index]
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? raw.height
            let bounds = CGRect(x: raw.minX, y: screenHeight - raw.minY - raw.height, width: raw.width, height: raw.height)
            return BG3Detection(isRunning: true, displayName: owner.isEmpty ? title : owner, detail: "Matched visible BG3 window", windowFrame: bounds)
        }

        for app in NSWorkspace.shared.runningApplications {
            if Self.matchesIdentity(
                applicationName: app.localizedName ?? app.executableURL?.lastPathComponent ?? "",
                title: app.executableURL?.path ?? "",
                bundleIdentifier: app.bundleIdentifier ?? ""
            ) {
                return BG3Detection(isRunning: true, displayName: app.localizedName ?? "Baldur's Gate 3", detail: "Matched running BG3 process; no visible window", windowFrame: nil)
            }
        }
        return BG3Detection(isRunning: false, displayName: "Not detected", detail: "No BG3 process or visible window matched", windowFrame: nil)
    }
}
