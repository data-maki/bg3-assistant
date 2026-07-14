import SwiftUI

enum BG3Theme {
    static let ink = Color(red: 0.055, green: 0.047, blue: 0.036)
    static let umber = Color(red: 0.18, green: 0.13, blue: 0.085)
    static let bronze = Color(red: 0.55, green: 0.32, blue: 0.14)
    static let bronzeBright = Color(red: 0.72, green: 0.46, blue: 0.22)
    static let gold = Color(red: 0.91, green: 0.70, blue: 0.30)
    static let parchment = Color(red: 0.94, green: 0.89, blue: 0.76)
    static let mutedParchment = Color(red: 0.72, green: 0.67, blue: 0.56)
    static let success = Color(red: 0.40, green: 0.72, blue: 0.55)

    static let panelTint = LinearGradient(
        colors: [umber.opacity(0.74), ink.opacity(0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func dangerColor(_ danger: String) -> Color {
        danger == "extreme" ? .red : danger == "high" ? .orange : danger == "medium" ? .yellow : .cyan
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

    @ViewBuilder
    func assistantGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass).tint(BG3Theme.bronzeBright)
        } else {
            buttonStyle(.bordered).tint(BG3Theme.bronzeBright)
        }
    }

    func bg3InsetSurface(accent: Color = BG3Theme.bronze, cornerRadius: CGFloat = 9) -> some View {
        background(BG3Theme.ink.opacity(0.42), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.30), lineWidth: 0.7)
            }
    }
}
