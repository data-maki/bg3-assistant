import SwiftUI

/// Full-panel detail page for one route step, pushed from the Route list.
struct StepDetailView: View {
    @EnvironmentObject private var appState: AppState
    let stepId: String
    let onBack: () -> Void

    var body: some View {
        if let step = appState.walkthrough.first(where: { $0.id == stepId }) {
            detail(step)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                backButton
                Text("This step is no longer in the guide.")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                Spacer()
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Route", systemImage: "chevron.left").font(BG3Type.captionBold)
        }
        .assistantActionButton()
        .controlSize(.small)
    }

    private func detail(_ step: WalkthroughStep) -> some View {
        let encounter = StepEncounter.classify(step)
        let disposition = appState.walkthroughDisposition(step)
        let presentation = appState.routeDependencyPresentation(for: step)
        let focused = appState.focusedWalkthroughStep?.id == step.id
        let prerequisiteTitles = step.prerequisites.map { id in
            appState.walkthrough.first(where: { $0.id == id })?.title ?? id
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                backButton
                Spacer()
                Button {
                    appState.focusWalkthroughStep(step)
                } label: {
                    Label(focused ? "Focused" : "Set focus", systemImage: focused ? "scope" : "circle.dotted")
                        .font(BG3Type.captionBold)
                }
                .assistantActionButton(accent: focused ? BG3Theme.success : BG3Theme.control)
                .controlSize(.small)
                .help(focused ? "This is your current focus" : "Make this your current focus — the Now page follows it")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        StatusChip(text: encounter.label, tint: encounter.tint)
                        StatusChip(text: "L\(step.minimumLevel)+", tint: BG3Theme.mutedParchment)
                        if disposition == .completed { StatusChip(text: "done", tint: BG3Theme.success) }
                        if disposition == .skipped { StatusChip(text: "skipped", tint: BG3Theme.warning) }
                        Spacer()
                    }
                    Text(step.title)
                        .font(BG3Type.pageTitle)
                        .foregroundStyle(BG3Theme.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(step.phase) · \(step.area)")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)

                    Divider().overlay(BG3Theme.bronze.opacity(0.38))

                    if let note = presentation.note {
                        FactRow(
                            glyph: presentation.requiresAttention ? "⚠" : "◇",
                            tint: presentation.requiresAttention ? BG3Theme.warning : BG3Theme.mutedParchment,
                            text: note, secondary: true
                        )
                    }
                    FactRow(glyph: "→", tint: BG3Theme.gold, text: step.summary)
                    if !step.avoid.isEmpty {
                        FactRow(glyph: "✕", tint: BG3Theme.danger, text: step.avoid)
                    }
                    if !step.why.isEmpty {
                        FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: step.why, secondary: true)
                    }
                    if !step.rewards.isEmpty {
                        FactRow(glyph: "★", tint: BG3Theme.gold, text: step.rewards.joined(separator: " · "))
                    }
                    if !prerequisiteTitles.isEmpty {
                        FactRow(glyph: "◇", tint: BG3Theme.mutedParchment, text: "First: \(prerequisiteTitles.joined(separator: " · "))", secondary: true)
                    }
                    if !step.completionChecks.isEmpty {
                        FactRow(glyph: "✓", tint: BG3Theme.success, text: "Done when: \(step.completionChecks.joined(separator: " · "))", secondary: true)
                    }
                    if let outcome = appState.walkthroughOutcome(step) {
                        FactRow(glyph: "✓", tint: BG3Theme.success, text: "Outcome: \(outcome)")
                    }
                    if let decision = step.decision {
                        DecisionCard(decision: decision, step: step, showsActions: disposition != .completed)
                    }
                    if let incident = appState.incidentProtocol(for: step) {
                        incidentProtocolCard(incident)
                    }
                    if let riskReward = step.riskReward {
                        riskRewardCard(riskReward)
                    }
                    if let source = URL(string: step.sourceUrl) {
                        Link("\(step.sourceLabel) ↗", destination: source).font(BG3Type.caption)
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 4)
            }
            Divider().overlay(BG3Theme.bronze.opacity(0.38))
            actionBar(step, disposition: disposition)
                .padding(.top, 6)
        }
    }

    @ViewBuilder private func actionBar(_ step: WalkthroughStep, disposition: CheckpointDisposition) -> some View {
        HStack(spacing: 6) {
            if step.decision == nil, disposition != .completed {
                Button {
                    appState.setWalkthroughDisposition(step, .completed)
                } label: {
                    Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: true)
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            if disposition == .pending {
                Button {
                    appState.setWalkthroughDisposition(step, .skipped)
                } label: {
                    Label("Skip", systemImage: "forward.end")
                }
                .assistantActionButton()
                .frame(minHeight: 32)
                .fixedSize()
            } else {
                Button {
                    appState.setWalkthroughDisposition(step, .pending)
                } label: {
                    Label("Revisit", systemImage: "arrow.uturn.backward")
                }
                .assistantActionButton()
                .frame(minHeight: 32)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

}
