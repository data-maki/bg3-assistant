import AppKit
import Foundation
import ScreenCaptureKit

@main
enum BG3DebugCapture {
    static func main() async throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "BG3DebugCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: bg3-debug-capture <output.jpg>"])
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let windows = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.larian.bg3" }
        for candidate in windows {
            print("Candidate \(candidate.title ?? "<untitled>") • \(Int(candidate.frame.width))x\(Int(candidate.frame.height))")
        }
        guard let window = windows.max(by: { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }) else {
            throw NSError(domain: "BG3DebugCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "No visible com.larian.bg3 window"])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 1
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NSError(domain: "BG3DebugCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "JPEG encoding failed"])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
        print("Captured \(window.title ?? "BG3") at \(image.width)x\(image.height) to \(output.path)")
    }
}
