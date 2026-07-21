import SwiftUI

/// One roster member with the Active/Camp/Unrecruited status menu. Shared by
/// the Party tab's setup page and the onboarding wizard's party step so the
/// two can never drift.
struct PartyRosterRow: View {
    @EnvironmentObject private var appState: AppState
    let member: PartyMember

    private var active: [PartyMember] {
        appState.roster.filter { $0.rosterStatus == .active }
    }

    var body: some View {
        HStack(spacing: 9) {
            PartyMemberAvatar(member: member, size: 27, accent: member.rosterStatus.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(BG3Type.rowTitle)
                    .foregroundStyle(BG3Theme.parchment)
                    .lineLimit(1)
                Text("L\(member.level) · \(memberDetail)")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            statusMenu
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .bg3InsetSurface(accent: member.rosterStatus.tint)
        .accessibilityElement(children: .contain)
    }

    private var statusMenu: some View {
        Menu {
            if member.rosterStatus == .active {
                Label("Active", systemImage: "checkmark")
            } else if member.rosterStatus.canBeActive {
                if active.count < 4 {
                    Button {
                        _ = appState.setRosterStatus(.active, for: member)
                    } label: {
                        Label("Active", systemImage: "figure.walk")
                    }
                } else {
                    Menu("Active, replacing...") {
                        ForEach(active) { outgoing in
                            Button(outgoing.name) {
                                _ = appState.swapIntoActive(member, replacing: outgoing)
                            }
                        }
                    }
                }
            } else {
                Button("Active") {}
                    .disabled(true)
            }

            if member.rosterStatus == .camp {
                Label("Camp", systemImage: "checkmark")
            } else {
                Button {
                    _ = appState.setRosterStatus(.camp, for: member)
                } label: {
                    Label("Camp", systemImage: "tent")
                }
            }

            if member.rosterStatus == .unrecruited {
                Label(RosterStatus.unrecruited.label, systemImage: "checkmark")
            } else {
                Button {
                    _ = appState.setRosterStatus(.unrecruited, for: member)
                } label: {
                    Label(RosterStatus.unrecruited.label, systemImage: "person.crop.circle.badge.minus")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(member.rosterStatus.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(BG3Type.captionBold)
            .foregroundStyle(member.rosterStatus.tint)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(member.rosterStatus.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(member.rosterStatus.tint.opacity(0.45), lineWidth: 0.7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("\(member.name) roster status")
        .accessibilityValue(member.rosterStatus.label)
    }

    private var memberDetail: String {
        if member.isHireling == true,
           let hireling = WithersHireling.matching(member.name) {
            return "\(hireling.race) · \(hireling.defaultClass)"
        }
        return member.className ?? "Party member"
    }
}

struct PartyMemberAvatar: View {
    let member: PartyMember
    let size: CGFloat
    let accent: Color

    var body: some View {
        Group {
            if let portrait {
                Image(nsImage: portrait)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(member.monogramInitials)
                    .font(.system(size: size * 0.37, weight: .heavy, design: .serif))
                    .foregroundStyle(BG3Theme.parchment)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(accent.opacity(0.22))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25)
                .stroke(accent.opacity(0.55), lineWidth: 0.7)
        )
        .accessibilityHidden(true)
    }

    private var portrait: NSImage? {
        guard let filename = Self.filenames[member.name.lowercased()],
              let url = Bundle.main.url(
                  forResource: filename,
                  withExtension: "png",
                  subdirectory: "CompanionPortraits"
              ) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static let filenames = [
        "shadowheart": "shadowheart",
        "lae'zel": "laezel",
        "astarion": "astarion",
        "gale": "gale",
        "wyll": "wyll",
        "karlach": "karlach",
        "dark urge": "dark-urge",
        "halsin": "halsin",
        "minthara": "minthara",
        "jaheira": "jaheira",
        "minsc": "minsc",
    ]
}
