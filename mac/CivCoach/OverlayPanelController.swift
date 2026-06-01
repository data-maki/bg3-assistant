import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private var panel: NSPanel?
    private let collapsedSize = NSSize(width: 88, height: 46)
    private let expandedSize = NSSize(width: 320, height: 360)

    func show(appState: AppState) {
        if panel == nil {
            let rootView = OverlayView()
                .environmentObject(appState)
            let hostingController = NSHostingController(rootView: rootView)
            let newPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: appState.overlayExpanded ? expandedSize : collapsedSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.contentViewController = hostingController
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.level = .screenSaver
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.hidesOnDeactivate = false
            panel = newPanel
        }

        panel?.setContentSize(appState.overlayExpanded ? expandedSize : collapsedSize)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let screen = NSScreen.main, let panel else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 32
        let y = visible.maxY - panel.frame.height - 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
