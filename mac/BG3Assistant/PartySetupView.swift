import SwiftUI

struct PartySetupView: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void

    private var active: [PartyMember] {
        appState.roster.filter { $0.rosterStatus == .active }
    }

    private var members: [PartyMember] {
        appState.roster.sorted { lhs, rhs in
            let lhsRank = lhs.rosterStatus.sortRank
            let rhsRank = rhs.rosterStatus.sortRank
            return lhsRank == rhsRank
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhsRank < rhsRank
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(members) { member in memberRow(member) }
                }
                .padding(.trailing, 6)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Label("Party", systemImage: "chevron.left").font(BG3Type.captionBold)
                }
                .assistantActionButton()
                .controlSize(.small)
                Spacer()
                Text("\(active.count)/4 active")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("MANAGE PARTY MEMBERS")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Text("Choose Active, Camp, or Unrecruited")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
        }
    }

    private func memberRow(_ member: PartyMember) -> some View {
        HStack(spacing: 9) {
            Text(member.monogramInitials)
                .font(.system(size: 10, weight: .heavy, design: .serif))
                .foregroundStyle(BG3Theme.parchment)
                .frame(width: 27, height: 27)
                .background(member.rosterStatus.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(member.rosterStatus.tint.opacity(0.55), lineWidth: 0.7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(BG3Type.rowTitle)
                    .foregroundStyle(BG3Theme.parchment)
                    .lineLimit(1)
                Text("L\(member.level) · \(memberDetail(member))")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            statusMenu(member)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .bg3InsetSurface(accent: member.rosterStatus.tint)
        .accessibilityElement(children: .contain)
    }

    private func statusMenu(_ member: PartyMember) -> some View {
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

    private func memberDetail(_ member: PartyMember) -> String {
        if member.isHireling == true,
           let hireling = WithersHireling.matching(member.name) {
            return "\(hireling.race) · \(hireling.defaultClass)"
        }
        return member.className ?? "Party member"
    }

}
