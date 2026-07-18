import SwiftUI

/// Glance-first Party guidance. Configuration lives on pushed setup/detail
/// pages so the landing page answers one question: what does everyone do now?
struct PartyTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = PartyPage.guidance
    @State private var pendingResetMemberID: String?

    private enum PartyPage: Equatable {
        case guidance
        case setup
        case member(String)
        case abilities(String)
    }

    var body: some View {
        VStack(spacing: 7) {
            if let error = appState.errorMessage { errorBanner(error) }
            if let undo = appState.partyUndoState { undoBanner(undo) }
            ZStack {
                switch page {
                case .guidance:
                    PartyGuidanceView(
                        onMember: { page = .member($0) },
                        onSetup: { page = .setup }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                case .setup:
                    PartySetupView(onBack: { page = .guidance })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .member(let memberID):
                    PartyMemberDetailView(
                        memberID: memberID,
                        onBack: { page = .guidance },
                        onAbilities: { page = .abilities(memberID) },
                        onReset: { pendingResetMemberID = memberID }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .abilities(let memberID):
                    PartyAbilityRecipeView(
                        memberID: memberID,
                        onBack: { page = .member(memberID) }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
        .alert(item: $appState.pendingRosterStatusChange) { pending in
            Alert(
                title: Text("Confirm \(pending.memberName) · \(pending.target == .dead ? "Dead" : "Departed")"),
                message: Text(pending.message),
                primaryButton: .destructive(Text(pending.target == .dead ? "Mark dead" : "Mark departed")) {
                    appState.confirmRosterStatusChange()
                },
                secondaryButton: .cancel { appState.cancelRosterStatusChange() }
            )
        }
        .confirmationDialog(
            "Reset this character plan?",
            isPresented: Binding(
                get: { pendingResetMemberID != nil },
                set: { if !$0 { pendingResetMemberID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset build, recorded stats, and equipment", role: .destructive) {
                guard let id = pendingResetMemberID,
                      let member = appState.roster.first(where: { $0.id == id }) else { return }
                appState.respec(member)
                pendingResetMemberID = nil
                page = .guidance
            }
            Button("Cancel", role: .cancel) { pendingResetMemberID = nil }
        } message: {
            Text("This is a planner reset, not a Withers respec. It removes the assigned build, recorded ability sources, and equipped-item confirmations.")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BG3Theme.warning)
            Text(message)
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.parchment)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                appState.errorMessage = nil
            } label: {
                Image(systemName: "xmark").accessibilityLabel("Dismiss error")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .bg3InsetSurface(accent: BG3Theme.warning)
    }

    private func undoBanner(_ undo: PartyUndoState) -> some View {
        HStack(spacing: 7) {
            Text(undo.message)
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo") { appState.undoLastPartyChange() }
                .buttonStyle(.plain)
                .font(BG3Type.captionBold)
                .foregroundStyle(BG3Theme.gold)
            Button {
                appState.partyUndoState = nil
            } label: {
                Image(systemName: "xmark").accessibilityLabel("Dismiss undo")
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .bg3InsetSurface(accent: BG3Theme.control)
    }
}

private struct PartyGuidanceView: View {
    @EnvironmentObject private var appState: AppState
    let onMember: (String) -> Void
    let onSetup: () -> Void

    private var activeMembers: [PartyMember] { appState.activeParty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                LazyVStack(spacing: 7) {
                    if activeMembers.isEmpty { emptyState }
                    ForEach(activeMembers) { member in guidanceRow(member) }
                }
                .padding(.trailing, 6)
            }
            Button(action: onSetup) {
                HStack {
                    Label("Manage party members", systemImage: "person.3.sequence")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(BG3Type.captionBold)
                .frame(maxWidth: .infinity)
            }
            .assistantActionButton(accent: BG3Theme.gold, prominent: true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("ACTIVE PARTY")
                .font(BG3Type.overline)
                .foregroundStyle(BG3Theme.gold)
            Text("Level guidance")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
            Spacer()
            Text("\(activeMembers.count)/4 active")
                .font(BG3Type.captionBold)
                .foregroundStyle(BG3Theme.mutedParchment)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("No active party members")
                .font(BG3Type.rowTitle)
            Text("A solo run is valid, but at least one active character is needed for Party guidance.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
            Button("Open Party setup", action: onSetup)
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func guidanceRow(_ member: PartyMember) -> some View {
        let build = appState.builds.first { $0.id == member.buildId }
        let step = build?.levels.last { $0.level <= member.level }
        let exact = step?.level == member.level
        let setup = AbilityProgression.activeSetup(in: build, at: member.level)
        let setupApplied = setup.map { member.appliedAbilitySetupId == $0.id } ?? false
        let setupDue = setup != nil && !setupApplied
        let instruction = step.map { step in
            if !step.choices.isEmpty, step.choices != "-" {
                return "\(step.take) · \(step.choices)"
            }
            return step.take
        }

        return Button { onMember(member.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    memberMonogram(member)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(member.name)
                                .font(BG3Type.rowTitle)
                                .foregroundStyle(BG3Theme.parchment)
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            if setupDue {
                                Label("Set abilities", systemImage: "exclamationmark.circle.fill")
                                    .font(BG3Type.captionBold)
                                    .foregroundStyle(BG3Theme.warning)
                                    .lineLimit(1)
                            }
                        }
                        Text("L\(member.level) · \(build?.name ?? member.className ?? "No build")")
                            .font(BG3Type.caption)
                            .foregroundStyle(BG3Theme.mutedParchment)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BG3Theme.mutedParchment)
                }

                if let step, let instruction {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        StatusChip(text: exact ? "NOW L\(step.level)" : "LATEST L\(step.level)", tint: exact ? BG3Theme.success : BG3Theme.control, filled: exact)
                        Text(instruction)
                            .font(BG3Type.captionBold)
                            .foregroundStyle(BG3Theme.parchment)
                            .lineLimit(1)
                    }
                    if !step.tactics.isEmpty, step.tactics != "-" {
                        FactRow(glyph: "◆", tint: BG3Theme.success, text: step.tactics, secondary: true)
                            .lineLimit(1)
                    }
                } else {
                    HStack {
                        Label("Choose a reviewed build", systemImage: "exclamationmark.triangle.fill")
                            .font(BG3Type.captionBold)
                            .foregroundStyle(BG3Theme.warning)
                        Spacer()
                        Text("Choose ›").font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold)
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bg3InsetSurface(accent: exact ? BG3Theme.success : build == nil ? BG3Theme.warning : BG3Theme.bronze)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open \(member.name) details")
    }

    private func memberMonogram(_ member: PartyMember) -> some View {
        Text(member.monogramInitials)
            .font(.system(size: 11, weight: .heavy, design: .serif))
            .foregroundStyle(BG3Theme.parchment)
            .frame(width: 30, height: 30)
            .background(BG3Theme.bronze.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BG3Theme.gold.opacity(0.42), lineWidth: 0.7))
            .accessibilityHidden(true)
    }
}
