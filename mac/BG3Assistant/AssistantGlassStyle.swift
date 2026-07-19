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
    static let fightTint = Color(red: 0.92, green: 0.42, blue: 0.34)
    static let talkTint = Color(red: 0.55, green: 0.78, blue: 0.95)

    // Gear rarity palette (BG3's item-frame colors).
    static let rarityLegendary = Color(red: 1.0, green: 0.58, blue: 0.16)
    static let rarityVeryRare = Color(red: 0.73, green: 0.48, blue: 1.0)
    static let rarityRare = Color(red: 0.34, green: 0.62, blue: 1.0)
    static let rarityUncommon = Color(red: 0.42, green: 0.78, blue: 0.38)

    // Region-cluster palette for gear location tinting.
    static let clusterWilderness = Color(red: 0.43, green: 0.60, blue: 0.44)
    static let clusterSettlement = Color(red: 0.65, green: 0.55, blue: 0.39)
    static let clusterHostile = Color(red: 0.68, green: 0.42, blue: 0.39)
    static let clusterUnderdark = Color(red: 0.56, green: 0.49, blue: 0.68)
    static let clusterForge = Color(red: 0.70, green: 0.49, blue: 0.31)
    static let clusterMountainPass = Color(red: 0.43, green: 0.60, blue: 0.68)
    static let clusterRivington = Color(red: 0.66, green: 0.46, blue: 0.58)

    static let panelTint = LinearGradient(
        colors: [umber.opacity(0.74), ink.opacity(0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func dangerColor(_ danger: String) -> Color {
        danger == "extreme" ? self.danger : danger == "high" ? warning : danger == "medium" ? caution : control
    }
}

/// The five-step type scale. Nothing in the overlay renders below 9pt.
enum BG3Type {
    /// Section headers only — at most one per card.
    static let overline = Font.system(size: 9, weight: .heavy, design: .serif)
    static let caption = Font.system(size: 10)
    static let captionBold = Font.system(size: 10, weight: .semibold)
    static let body = Font.system(size: 12)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let pageTitle = Font.system(size: 17, weight: .bold, design: .serif)
    /// Peek-card headline only: the collapsed overlay's one serif title.
    static let peekTitle = Font.system(size: 13, weight: .bold, design: .serif)
}

/// Icon-gutter fact row: a fixed glyph column so stacked facts align without
/// per-fact caps labels. Glyphs carry the meaning: → do, ✕ avoid, ◆ why,
/// ★ reward, ◈ gear.
struct FactRow: View {
    let glyph: String
    let tint: Color
    let text: String
    var secondary = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(glyph)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(secondary ? BG3Type.caption : BG3Type.body)
                .foregroundStyle(secondary ? BG3Theme.mutedParchment : BG3Theme.parchment)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small status capsule ("now", "ready", "L4", "later", "revisit").
struct StatusChip: View {
    let text: String
    let tint: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .serif))
            .foregroundStyle(filled ? BG3Theme.parchment : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(tint.opacity(filled ? 0.34 : 0.13), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.7))
    }
}

extension StepEncounter {
    /// Theme role for the encounter icon: fight red-orange, talk blue.
    var tint: Color {
        switch self {
        case .fight: BG3Theme.fightTint
        case .talk: BG3Theme.talkTint
        case .fightAndTalk: BG3Theme.warning
        case .explore, .pickup, .gate: BG3Theme.mutedParchment
        }
    }
}

extension RosterStatus {
    var label: String {
        switch self {
        case .active: "Active"
        case .camp: "Camp"
        case .unrecruited: "Not recruited"
        case .unavailable: "Unavailable"
        case .dead: "Dead"
        case .departed: "Departed"
        }
    }

    var tint: Color {
        switch self {
        case .active: BG3Theme.success
        case .camp: BG3Theme.bronzeBright
        case .unrecruited: BG3Theme.gold
        case .unavailable, .dead, .departed: BG3Theme.danger
        }
    }

    /// Grouping order for roster lists: active party first, gone members last.
    var sortRank: Int {
        switch self {
        case .active: 0
        case .camp: 1
        case .unrecruited: 2
        case .unavailable, .dead, .departed: 3
        }
    }
}

extension PartyMember {
    /// Up to two initials for the member's monogram tile.
    var monogramInitials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// Collapsible section: icon/glyph + title + chevron toggle, then content.
struct BG3Disclosure<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var glyph: String? = nil
    var tint: Color = BG3Theme.mutedParchment
    var titleTint: Color = BG3Theme.parchment
    var inset = false
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if inset {
            core.padding(8).bg3InsetSurface(accent: tint.opacity(0.6))
        } else {
            core
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(tint)
                    } else if let glyph {
                        Text(glyph).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                    }
                    Text(title).font(BG3Type.captionBold).foregroundStyle(titleTint)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(BG3Theme.mutedParchment)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded { content() }
        }
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
        #if compiler(>=6.2)
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
        #else
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background { shape.fill(BG3Theme.panelTint) }
            .overlay { BG3FrameOverlay(cornerRadius: cornerRadius) }
        #endif
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
