import CoreGraphics
import Foundation

struct PetSpriteFrame: Equatable {
    let row: Int
    let column: Int
}

enum PetAnimationModel {
    // Matches the authored Codex v2 atlas timings.
    static let idleDurations = [280, 110, 110, 140, 140, 320]
    static let jumpingDurations = [140, 140, 140, 140, 280]

    static var hoverIntroDuration: TimeInterval {
        TimeInterval(jumpingDurations.reduce(0, +)) / 1_000
    }

    static func frame(
        isHovered: Bool,
        hoverElapsed: TimeInterval,
        pointerLocation: CGPoint?,
        viewSize: CGSize,
        reduceMotion: Bool
    ) -> PetSpriteFrame {
        guard isHovered else { return PetSpriteFrame(row: 0, column: 0) }

        if !reduceMotion, hoverElapsed < hoverIntroDuration {
            return PetSpriteFrame(
                row: 4,
                column: animationColumn(elapsed: hoverElapsed, durations: jumpingDurations)
            )
        }

        if let pointerLocation,
           let lookFrame = lookFrame(pointerLocation: pointerLocation, viewSize: viewSize) {
            return lookFrame
        }

        guard !reduceMotion else { return PetSpriteFrame(row: 0, column: 0) }
        return PetSpriteFrame(
            row: 0,
            column: animationColumn(
                elapsed: max(0, hoverElapsed - hoverIntroDuration),
                durations: idleDurations
            )
        )
    }

    static func lookFrame(pointerLocation: CGPoint, viewSize: CGSize) -> PetSpriteFrame? {
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let dx = pointerLocation.x - center.x
        let dy = pointerLocation.y - center.y
        let deadzone = min(viewSize.width, viewSize.height) * 0.14
        guard hypot(dx, dy) > deadzone else { return nil }

        // SwiftUI's y axis points down. atan2(dx, -dy) makes 000 point up
        // and advances clockwise, matching v2 rows 9 and 10.
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let directionIndex = Int(floor((degrees + 11.25) / 22.5)) % 16
        return PetSpriteFrame(
            row: directionIndex < 8 ? 9 : 10,
            column: directionIndex % 8
        )
    }

    private static func animationColumn(elapsed: TimeInterval, durations: [Int]) -> Int {
        let total = durations.reduce(0, +)
        guard total > 0 else { return 0 }
        var remaining = Int(max(0, elapsed) * 1_000) % total
        for (column, duration) in durations.enumerated() {
            if remaining < duration { return column }
            remaining -= duration
        }
        return max(0, durations.count - 1)
    }
}
