import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotResult {
    let data: Data
    let width: Int
    let height: Int
}

actor ScreenCaptureService {
    func captureBG3Window() async throws -> ScreenshotResult {
        let image = try await captureCGImage()
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
            throw BG3AssistantError.imageEncodingFailed
        }
        return ScreenshotResult(data: data, width: image.width, height: image.height)
    }

    private func captureCGImage() async throws -> CGImage {
        // BG3 commonly runs in its own fullscreen Space. Restricting discovery
        // to the assistant's current Space makes an authorized window look absent.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let matches = content.windows.filter { candidate in
            BG3Detector.matchesIdentity(
                applicationName: candidate.owningApplication?.applicationName ?? "",
                title: candidate.title ?? "",
                bundleIdentifier: candidate.owningApplication?.bundleIdentifier ?? ""
            )
        }
        guard let index = BG3Detector.largestFrameIndex(matches.map(\.frame)) else {
            throw BG3AssistantError.bg3WindowNotFound
        }
        let window = matches[index]

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let captureSize = BG3Detector.capturePixelSize(for: window.frame)
        configuration.width = captureSize.width
        configuration.height = captureSize.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }
        configuration.queueDepth = 1
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
