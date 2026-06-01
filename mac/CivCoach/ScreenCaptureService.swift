import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotResult {
    let data: Data
    let width: Int
    let height: Int
}

struct ScreenCaptureService {
    func capture() async throws -> ScreenshotResult {
        let image = try await captureCGImage()
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
            throw CivCoachError.imageEncodingFailed
        }
        return ScreenshotResult(data: data, width: image.width, height: image.height)
    }

    private func captureCGImage() async throws -> CGImage {
        let content = try await SCShareableContent.current
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw CivCoachError.screenCaptureFailed
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }
        configuration.queueDepth = 1
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
