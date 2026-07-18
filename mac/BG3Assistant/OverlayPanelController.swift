import AppKit
import SwiftUI

/// A borderless panel that can still take keyboard focus. `NSPanel` returns
/// `canBecomeKey == false` for borderless styles by default, which silently
/// blocks every text field in the overlay (you can't type in chat). Combined
/// with `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded`, this lets a clicked
/// text field become first responder without stealing activation from BG3.
private final class KeyableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A transparent zone that moves the whole overlay window when dragged. Placed
/// behind non-interactive content (pet, grip, status text) so the collapsed
/// card is draggable everywhere that is not a button.
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Wraps display-only content so its whole area acts as a window drag handle.
/// The handle is an overlay sized to the content, so it never expands the
/// layout (an NSViewRepresentable used as a ZStack sibling greedily fills the
/// parent's proposal and wrecks surrounding layout).
struct DraggableArea<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.overlay(WindowDragHandle())
    }
}

@MainActor
final class OverlayPanelController {
    private var panel: NSPanel?
    private var moveObserver: Any?
    private var isProgrammaticMove = false
    private var expectedProgrammaticOrigin: CGPoint?
    private var lastReference: CGRect = .zero
    private static let anchorKey = "BG3PetAnchorRel"
    private static let anchorVersionKey = "BG3PetAnchorVersion"
    private static let anchorVersion = 7

    func show(appState: AppState, gameFrame: CGRect?) {
        let reference = gameFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        lastReference = reference
        let targetSize = OverlayMetrics.panelSize(
            expanded: appState.overlayExpanded,
            reference: reference,
            tab: appState.plannerTab,
            density: appState.effectiveOverlayDensity,
            moreContextExpanded: appState.moreContextExpanded,
            onboarding: appState.onboardingStep != nil,
            hint: appState.onboardingStep == nil && appState.activeHint != nil
        )
        let persistedAnchor = savedAnchor()

        if panel == nil {
            let rootView = OverlayView()
                .environmentObject(appState)
            let hostingController = NSHostingController(rootView: rootView)
            let newPanel = KeyableOverlayPanel(
                contentRect: NSRect(origin: .zero, size: targetSize),
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
            newPanel.isMovableByWindowBackground = true
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.isReleasedWhenClosed = false
            panel = newPanel
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: newPanel, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.userMovedPanel() }
            }
        }

        guard let panel else { return }
        if panel.frame.size != targetSize {
            // A hosting controller may resize a newly created panel before its
            // first placement. Never persist that transient zero-origin frame.
            isProgrammaticMove = true
            panel.setContentSize(targetSize)
            isProgrammaticMove = false
        }

        let origin: CGPoint
        if let persistedAnchor {
            origin = OverlayMetrics.origin(fromNormalizedAnchor: persistedAnchor, panelSize: targetSize, reference: reference)
        } else {
            origin = OverlayMetrics.defaultOrigin(panelSize: targetSize, reference: reference)
            saveAnchor(for: origin, panelSize: targetSize, reference: reference)
        }
        let clampedOrigin = OverlayMetrics.clampedOrigin(origin, panelSize: targetSize, reference: reference)
        expectedProgrammaticOrigin = clampedOrigin
        isProgrammaticMove = true
        panel.setFrameOrigin(clampedOrigin)
        isProgrammaticMove = false
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Anchor persistence
    //
    // The overlay position is stored as a fraction of the game window's free
    // space, so it stays proportionally placed when the window moves, or when
    // the same run continues on a different display size.

    private func userMovedPanel() {
        guard !isProgrammaticMove, let panel else { return }
        let origin = panel.frame.origin
        if let expectedProgrammaticOrigin,
           abs(origin.x - expectedProgrammaticOrigin.x) < 0.5,
           abs(origin.y - expectedProgrammaticOrigin.y) < 0.5 {
            self.expectedProgrammaticOrigin = nil
            return
        }
        expectedProgrammaticOrigin = nil
        saveAnchor(for: origin, panelSize: panel.frame.size, reference: lastReference)
    }

    private func saveAnchor(for origin: CGPoint, panelSize: CGSize, reference: CGRect) {
        let anchor = OverlayMetrics.normalizedAnchor(for: origin, panelSize: panelSize, reference: reference)
        UserDefaults.standard.set("\(anchor.x),\(anchor.y)", forKey: Self.anchorKey)
        UserDefaults.standard.set(Self.anchorVersion, forKey: Self.anchorVersionKey)
    }

    private func savedAnchor() -> CGPoint? {
        guard UserDefaults.standard.integer(forKey: Self.anchorVersionKey) == Self.anchorVersion else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: Self.anchorKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

}
