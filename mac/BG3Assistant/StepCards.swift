import SwiftUI

// Shared step-presentation components consumed by NowTabView, StepDetailView,
// and RouteTabView. One rendering per concept: decision trade-offs, the
// "Went differently" outcome menu, incident protocol, and risk/reward.

/// One decision option: label row plus benefit/cost lines.
/// `compact` renders the label only — used where space is tight.
struct DecisionOptionRows: View {
    let option: DecisionOption
    var recommended = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FactRow(
                glyph: recommended ? "✓" : "⑂",
                tint: recommended ? BG3Theme.success : BG3Theme.mutedParchment,
                text: option.label,
                secondary: compact
            )
            if !compact {
                if !option.benefits.isEmpty {
                    FactRow(glyph: "＋", tint: BG3Theme.success, text: option.benefits.joined(separator: " · "), secondary: true)
                }
                if !option.costs.isEmpty {
                    FactRow(glyph: "－", tint: BG3Theme.warning, text: option.costs.joined(separator: " · "), secondary: true)
                }
            }
        }
    }
}

/// "Went differently" alternatives menu — resolves the step with the chosen outcome.
struct WentDifferentlyMenu: View {
    @EnvironmentObject private var appState: AppState
    let step: WalkthroughStep
    let decision: WalkthroughDecision

    var body: some View {
        Menu {
            ForEach(decision.alternatives, id: \.label) { option in
                Button(option.label) { appState.resolveWalkthroughStep(step, outcome: option.label) }
            }
        } label: {
            Label("Went differently", systemImage: "arrow.triangle.branch")
        }
        .assistantActionButton()
    }
}

/// The decision card: authority overline, prompt, trade-offs, reversibility,
/// and optionally the outcome controls inline.
struct DecisionCard: View {
    @EnvironmentObject private var appState: AppState
    let decision: WalkthroughDecision
    let step: WalkthroughStep
    var compactAlternatives = false
    var showsActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(decision.authority == "guide_fact" ? "Decision — guide fact" : "Decision — assistant suggestion")
                .font(BG3Type.overline)
                .foregroundStyle(BG3Theme.gold)
            Text(decision.prompt)
                .font(BG3Type.rowTitle)
                .foregroundStyle(BG3Theme.parchment)
                .fixedSize(horizontal: false, vertical: true)
            DecisionOptionRows(option: decision.recommended, recommended: true)
            ForEach(decision.alternatives, id: \.label) {
                DecisionOptionRows(option: $0, compact: compactAlternatives)
            }
            Text(decision.reversible ? "Reversible" : "Irreversible")
                .font(BG3Type.captionBold)
                .foregroundStyle(decision.reversible ? BG3Theme.success : BG3Theme.warning)
            if showsActions {
                Button {
                    appState.resolveWalkthroughStep(step, outcome: decision.recommended.label)
                } label: {
                    Label(decision.recommended.label, systemImage: "checkmark")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: true)
                if !decision.alternatives.isEmpty {
                    WentDifferentlyMenu(step: step, decision: decision)
                        .controlSize(.small)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }
}

@MainActor
func incidentProtocolCard(_ incident: IncidentProtocol) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("Run-ender protocol")
            .font(BG3Type.overline).textCase(.uppercase).foregroundStyle(BG3Theme.danger)
        FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: "Trigger: \(incident.trigger)", secondary: true)
        ForEach(incident.safeActions, id: \.self) {
            FactRow(glyph: "→", tint: BG3Theme.success, text: $0, secondary: true)
        }
        FactRow(glyph: "✕", tint: BG3Theme.danger, text: "Never: \(incident.never)", secondary: true)
        FactRow(glyph: "⚠", tint: BG3Theme.warning, text: "If it goes wrong: \(incident.escape)", secondary: true)
        if !incident.honorDelta.isEmpty {
            FactRow(glyph: "★", tint: BG3Theme.gold, text: incident.honorDelta, secondary: true)
        }
        if let source = URL(string: incident.sourceUrl), !incident.sourceUrl.isEmpty {
            Link("Incident source ↗", destination: source).font(BG3Type.caption)
        }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .bg3InsetSurface(accent: BG3Theme.danger)
}

@MainActor
func riskRewardCard(_ riskReward: RiskReward) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        FactRow(glyph: "★", tint: BG3Theme.success, text: "Reward: \(riskReward.reward)", secondary: true)
        FactRow(glyph: "✕", tint: BG3Theme.danger, text: "Risk: \(riskReward.risk)", secondary: true)
        FactRow(glyph: "－", tint: BG3Theme.mutedParchment, text: "If skipped: \(riskReward.skipCost)", secondary: true)
        FactRow(glyph: "↩", tint: BG3Theme.mutedParchment, text: "Return by: \(riskReward.returnBy)", secondary: true)
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .bg3InsetSurface(accent: BG3Theme.bronze)
}
