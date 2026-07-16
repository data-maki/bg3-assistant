import CoreGraphics

/// Sizes and default placement for the assistant overlay, derived from the BG3
/// window so the overlay scales sensibly from a 13" MacBook up to an XL
/// external display. All rects are AppKit (bottom-left origin) coordinates.
enum OverlayMetrics {
    /// Fraction of the game window height covered by BG3's bottom HUD
    /// (hotbar, spell selection, end-turn controls).
    static let hotbarBand: CGFloat = 0.19
    /// Fraction of the game window height covered by the top-right minimap.
    static let minimapBand: CGFloat = 0.27
    static let edgeMargin: CGFloat = 14

    static func scale(for reference: CGRect) -> CGFloat {
        guard reference.height > 0 else { return 1 }
        // 1.0 at ~1000pt-high window (14" MacBook); clamped for small/huge screens.
        return min(max(reference.height / 1000, 0.85), 1.45)
    }

    static func collapsedSize(for reference: CGRect, density: OverlayDensity = .focus) -> CGSize {
        let s = scale(for: reference)
        if density == .minimal {
            return CGSize(width: 112, height: 86)
        }
        // A BG3-style horizontal tooltip: wide enough for the checkpoint and
        // one warning, short enough to stay between minimap and hotbar. The
        // height fits the 64pt pet portrait plus the icon shortcut row.
        let width = min(max(310 * s, 288), 336)
        let height = density == .reference ? min(max(170 * s, 162), 182) : min(max(150 * s, 142), 158)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    static func expandedSize(
        for reference: CGRect,
        tab: PlannerTab = .current,
        moreContextExpanded: Bool = false
    ) -> CGSize {
        let width = min(max(reference.width * 0.22, 420), 520)
        let height = switch tab {
        case .current: moreContextExpanded
            ? min(max(reference.height * 0.54, 550), 640)
            : min(max(reference.height * 0.255, 320), 350)
        case .party: min(max(reference.height * 0.58, 590), 680)
        case .route, .chat, .settings: min(max(reference.height * 0.54, 550), 640)
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    static func panelSize(
        expanded: Bool,
        reference: CGRect,
        tab: PlannerTab = .current,
        density: OverlayDensity = .focus,
        moreContextExpanded: Bool = false
    ) -> CGSize {
        expanded
            ? expandedSize(for: reference, tab: tab, moreContextExpanded: moreContextExpanded)
            : collapsedSize(for: reference, density: density)
    }

    static func origin(fromNormalizedAnchor anchor: CGPoint, panelSize: CGSize, reference: CGRect) -> CGPoint {
        let freeWidth = max(0, reference.width - panelSize.width)
        let freeHeight = max(0, reference.height - panelSize.height)
        return CGPoint(
            x: reference.minX + min(max(anchor.x, 0), 1) * freeWidth,
            y: reference.minY + min(max(anchor.y, 0), 1) * freeHeight
        )
    }

    static func normalizedAnchor(for origin: CGPoint, panelSize: CGSize, reference: CGRect) -> CGPoint {
        let freeWidth = max(1, reference.width - panelSize.width)
        let freeHeight = max(1, reference.height - panelSize.height)
        return CGPoint(
            x: min(max((origin.x - reference.minX) / freeWidth, 0), 1),
            y: min(max((origin.y - reference.minY) / freeHeight, 0), 1)
        )
    }

    /// Default origin: vertically centered against the right edge. If a very
    /// short game window cannot center the expanded planner above the hotbar,
    /// preserve the hotbar safety band instead.
    static func defaultOrigin(panelSize: CGSize, reference: CGRect) -> CGPoint {
        let x = reference.maxX - panelSize.width - edgeMargin
        let bottomLimit = reference.minY + reference.height * hotbarBand
        let centeredY = reference.midY - panelSize.height / 2
        let y = max(centeredY, bottomLimit)
        return CGPoint(x: x, y: min(y, reference.maxY - panelSize.height))
    }

    static func clampedOrigin(_ origin: CGPoint, panelSize: CGSize, reference: CGRect) -> CGPoint {
        let x = min(max(origin.x, reference.minX), max(reference.minX, reference.maxX - panelSize.width))
        let y = min(max(origin.y, reference.minY), max(reference.minY, reference.maxY - panelSize.height))
        return CGPoint(x: x, y: y)
    }
}
