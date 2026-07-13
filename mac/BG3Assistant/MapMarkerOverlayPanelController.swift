import AppKit
import SwiftUI

struct ScreenMarker: Identifiable {
    let id: String
    let label: String
    let point: CGPoint
    let danger: String
}

private struct MarkerCanvas: View {
    let markers: [ScreenMarker]

    var body: some View {
        GeometryReader { _ in
            ForEach(markers) { marker in
                VStack(spacing: 3) {
                    Circle()
                        .fill(marker.danger == "extreme" ? .red : marker.danger == "high" ? .orange : .cyan)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                    Text(marker.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.72))
                        .clipShape(Capsule())
                }
                .position(marker.point)
            }
        }
    }
}

@MainActor
final class MapMarkerOverlayPanelController {
    private var panel: NSPanel?

    func show(frame: CGRect, markers: [ScreenMarker]) {
        guard !markers.isEmpty else { hide(); return }
        if panel == nil {
            let newPanel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.ignoresMouseEvents = true
            newPanel.level = .screenSaver
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.hidesOnDeactivate = false
            panel = newPanel
        }
        panel?.setFrame(frame, display: true)
        panel?.contentViewController = NSHostingController(rootView: MarkerCanvas(markers: markers))
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
