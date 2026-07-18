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
                    ForEach(members) { member in PartyRosterRow(member: member) }
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
}
