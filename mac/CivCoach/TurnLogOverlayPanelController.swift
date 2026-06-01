import AppKit
import SwiftUI

@MainActor
final class TurnLogOverlayPanelController {
    private var panel: NSPanel?
    private let expandedSize = NSSize(width: 390, height: 620)
    private let minimizedSize = NSSize(width: 150, height: 54)

    func show(appState: AppState) {
        if panel == nil {
            let rootView = TurnLogOverlayView()
                .environmentObject(appState)
            let hostingController = NSHostingController(rootView: rootView)
            let newPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: appState.turnLogOverlayMinimized ? minimizedSize : expandedSize),
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

        panel?.setContentSize(appState.turnLogOverlayMinimized ? minimizedSize : expandedSize)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let screen = NSScreen.main, let panel else { return }
        let visible = screen.visibleFrame
        let x = visible.minX + 24
        let y = visible.maxY - panel.frame.height - 102
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
