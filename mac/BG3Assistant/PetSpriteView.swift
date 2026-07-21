import AppKit
import SwiftUI

struct PetSpriteView: View {
    var size: CGFloat = 84
    var attentionTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverStartedAt: Date?
    @State private var attentionStartedAt: Date?
    @State private var pointerLocation: CGPoint?

    private var viewSize: CGSize {
        CGSize(width: size, height: size * 1.08)
    }

    var body: some View {
        let animationStartedAt = hoverStartedAt ?? attentionStartedAt
        TimelineView(.animation(minimumInterval: 1 / 30, paused: animationStartedAt == nil)) { timeline in
            let frame = PetAnimationModel.frame(
                isHovered: animationStartedAt != nil,
                hoverElapsed: animationStartedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0,
                pointerLocation: hoverStartedAt == nil && attentionStartedAt != nil
                    ? CGPoint(x: viewSize.width * 1.3, y: viewSize.height * 0.45)
                    : pointerLocation,
                viewSize: viewSize,
                reduceMotion: reduceMotion
            )
            if let image = PetSpriteLoader.frame(row: frame.row, column: frame.column) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: viewSize.width, height: viewSize.height)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.indigo)
                    .frame(width: viewSize.width, height: viewSize.height)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                if hoverStartedAt == nil { hoverStartedAt = .now }
                pointerLocation = location
            case .ended:
                hoverStartedAt = nil
                pointerLocation = nil
            }
        }
        .task(id: attentionTrigger) {
            guard attentionTrigger > 0, !reduceMotion else { return }
            attentionStartedAt = .now
            defer { if Task.isCancelled { attentionStartedAt = nil } }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            attentionStartedAt = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Twilight Cleric companion")
        .accessibilityValue(animationStartedAt == nil ? "Resting" : "Awake")
        .accessibilityHint("Hover to wake the companion")
    }
}

enum PetSpriteLoader {
    private static let cellWidth = 192
    private static let cellHeight = 208
    private static let sheet: CGImage? = {
        let bundled = Bundle.main.url(forResource: "twilight-cleric", withExtension: "webp")
        let source = bundled ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/pets/twilight-cleric/spritesheet.webp")
        return NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    static func frame(row: Int, column: Int) -> NSImage? {
        guard let sheet,
              let cropped = sheet.cropping(to: CGRect(x: column * cellWidth, y: sheet.height - ((row + 1) * cellHeight), width: cellWidth, height: cellHeight)) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cellWidth, height: cellHeight))
    }
}
