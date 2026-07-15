import SwiftUI

enum BG3Theme {
    static let ink = Color(red: 0.055, green: 0.047, blue: 0.036)
    static let umber = Color(red: 0.18, green: 0.13, blue: 0.085)
    static let bronze = Color(red: 0.55, green: 0.32, blue: 0.14)
    static let bronzeBright = Color(red: 0.61, green: 0.41, blue: 0.23)
    static let gold = Color(red: 0.78, green: 0.63, blue: 0.37)
    static let parchment = Color(red: 0.94, green: 0.89, blue: 0.76)
    static let mutedParchment = Color(red: 0.72, green: 0.67, blue: 0.56)
    static let control = Color(red: 0.49, green: 0.57, blue: 0.58)
    static let success = Color(red: 0.38, green: 0.62, blue: 0.48)
    static let warning = Color(red: 0.78, green: 0.47, blue: 0.25)
    static let caution = Color(red: 0.72, green: 0.59, blue: 0.30)
    static let danger = Color(red: 0.78, green: 0.32, blue: 0.28)

    static let panelTint = LinearGradient(
        colors: [umber.opacity(0.74), ink.opacity(0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func dangerColor(_ danger: String) -> Color {
        danger == "extreme" ? self.danger : danger == "high" ? warning : danger == "medium" ? caution : control
    }
}

private struct AssistantActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let accent: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: prominent ? .bold : .semibold))
            .foregroundStyle(isEnabled ? BG3Theme.parchment : BG3Theme.mutedParchment.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                accent.opacity(isEnabled ? (prominent ? 0.28 : 0.10) : 0.05),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accent.opacity(isEnabled ? (prominent ? 0.78 : 0.48) : 0.24), lineWidth: prominent ? 1.1 : 0.8)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BG3FrameOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.stroke(BG3Theme.bronze.opacity(0.92), lineWidth: 1.5)
            shape.inset(by: 3).stroke(BG3Theme.gold.opacity(0.34), lineWidth: 0.65)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, BG3Theme.gold.opacity(0.72), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, cornerRadius + 8)
                Spacer()
            }
            .padding(.top, 3)
        }
        .allowsHitTesting(false)
    }
}

private struct AssistantGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background { shape.fill(BG3Theme.panelTint) }
                .glassEffect(.regular.tint(BG3Theme.umber.opacity(0.42)), in: .rect(cornerRadius: cornerRadius))
                .overlay { BG3FrameOverlay(cornerRadius: cornerRadius) }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background { shape.fill(BG3Theme.panelTint) }
                .overlay { BG3FrameOverlay(cornerRadius: cornerRadius) }
        }
    }
}

extension View {
    func assistantGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(AssistantGlassSurface(cornerRadius: cornerRadius))
    }

    func assistantActionButton(accent: Color = BG3Theme.control, prominent: Bool = false) -> some View {
        buttonStyle(AssistantActionButtonStyle(accent: accent, prominent: prominent))
    }

    func bg3InsetSurface(accent: Color = BG3Theme.bronze, cornerRadius: CGFloat = 9) -> some View {
        background(BG3Theme.ink.opacity(0.42), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.30), lineWidth: 0.7)
            }
    }
}
