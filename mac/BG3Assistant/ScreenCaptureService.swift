import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

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

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = captureConfiguration(frame: window.frame)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            // Some Metal game windows fail desktop-independent capture even
            // after Screen Recording access is granted. Capture only BG3's app
            // inside the matching display region as a privacy-safe fallback.
            guard let displayIndex = BG3Detector.largestIntersectionIndex(
                    of: window.frame,
                    in: content.displays.map(\.frame)
                  ) else {
                throw error
            }
            let display = content.displays[displayIndex]
            guard let sourceRect = BG3Detector.displaySourceRect(
                windowFrame: window.frame,
                displayFrame: display.frame
            ) else {
                throw error
            }
            if let processIdentifier = window.owningApplication?.processID,
               let game = NSRunningApplication(processIdentifier: processIdentifier),
               !game.isActive {
                game.activate(options: [.activateAllWindows])
                try await Task.sleep(for: .milliseconds(350))
            }
            let assistantBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedWindows = content.windows.filter { candidate in
                guard let assistantBundleIdentifier else { return false }
                return candidate.owningApplication?.bundleIdentifier == assistantBundleIdentifier
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let configuration = captureConfiguration(frame: sourceRect, scale: Double(filter.pointPixelScale))
            configuration.sourceRect = sourceRect
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    private func captureConfiguration(frame: CGRect, scale: Double = 1) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let captureSize = BG3Detector.capturePixelSize(
            for: CGRect(x: 0, y: 0, width: frame.width * scale, height: frame.height * scale)
        )
        configuration.width = captureSize.width
        configuration.height = captureSize.height
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
        }
        configuration.queueDepth = 1
        return configuration
    }
}
