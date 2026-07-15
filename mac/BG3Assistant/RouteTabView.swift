import SwiftUI

/// The planner's Route tab: the full Act 1 route grouped by phase, with
/// expandable step detail, decision outcomes, and the archive.
struct RouteTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedStepId: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    compactHeader

                    if let selectedStep {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("SELECTED · \(selectedStep.title)")
                                    .font(.system(size: 9, weight: .heavy, design: .serif))
                                    .foregroundStyle(BG3Theme.gold)
                                Spacer()
                                Button { selectedStepId = nil } label: {
                                    Image(systemName: "xmark").frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain).help("Close route detail")
                            }
                            routeStepDetail(selectedStep)
                        }
                        .padding(8)
                        .bg3InsetSurface(accent: appState.walkthroughBlockers(selectedStep).isEmpty ? BG3Theme.gold : .orange)
                    }

                    ForEach(routePhases, id: \.order) { phase in
                        HStack {
                            Text(phase.name.uppercased())
                            Spacer()
                            Text("\(phase.steps.count) LEFT")
                        }
                        .font(.system(size: 9, weight: .heavy, design: .serif))
                        .foregroundStyle(BG3Theme.gold)
                        .padding(.top, 5).padding(.horizontal, 4)
                        ForEach(phase.steps) { step in
                            routeStepRow(step).id(step.id)
                        }
                    }
                    if !appState.archivedWalkthroughSteps.isEmpty {
                        DisclosureGroup("Archive · \(appState.archivedWalkthroughSteps.count)") {
                            LazyVStack(spacing: 6) {
                                ForEach(appState.archivedWalkthroughSteps.sorted { $0.order > $1.order }) { step in
                                    archivedStepRow(step)
                                }
                            }.padding(.top, 6)
                        }
                        .font(.caption.bold())
                        .padding(9)
                        .bg3InsetSurface(accent: BG3Theme.bronze)
                    }
                }.padding(.trailing, 8)
            }
            .onAppear { focusRouteStep(proxy) }
            .onChange(of: appState.focusedWalkthroughStepId) { _, _ in focusRouteStep(proxy) }
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 5) {
            HStack {
                Text("ACT 1 ROUTE").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("\(appState.remainingCount) LEFT").font(.caption2.bold()).foregroundStyle(BG3Theme.mutedParchment)
                Button { appState.followRecommendedRoute() } label: {
                    Label("Recommended", systemImage: "location.fill").font(.caption2.bold())
                }
                .assistantActionButton().controlSize(.mini)
            }
            HStack(spacing: 5) {
                Image(systemName: appState.actTwoBlockers.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(appState.actTwoBlockers.isEmpty ? "ACT 2 GATE · clear" : "ACT 2 GATE · \(appState.actTwoBlockers.count) blocker(s)")
                Spacer()
                if let blocker = appState.actTwoBlockers.first { Text(blocker).lineLimit(1) }
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(appState.actTwoBlockers.isEmpty ? BG3Theme.success : .orange)
        }
        .padding(8).bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var routePhases: [(order: Int, name: String, steps: [WalkthroughStep])] {
        Dictionary(grouping: appState.activeWalkthroughSteps, by: \.phaseOrder)
            .sorted { $0.key < $1.key }
            .map { order, steps in
                (order, steps.first?.phase ?? "", steps.sorted { $0.order < $1.order })
            }
    }

    private func focusRouteStep(_ proxy: ScrollViewProxy) {
        guard let id = appState.focusedWalkthroughStepId else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
    }

    private var selectedStep: WalkthroughStep? {
        guard let selectedStepId else { return nil }
        return appState.walkthrough.first(where: { $0.id == selectedStepId })
    }

    private func routeStepRow(_ step: WalkthroughStep) -> some View {
        let isNext = step.id == appState.recommendedWalkthroughStep?.id
        let isFocused = step.id == appState.focusedWalkthroughStep?.id
        let isSelected = selectedStepId == step.id
        return RouteRailRow(
            step: step,
            blockers: appState.walkthroughBlockers(step),
            partyLevel: appState.lowestPartyLevel,
            isNext: isNext,
            isFocused: isFocused,
            isSelected: isSelected,
            onSelect: { selectedStepId = isSelected ? nil : step.id },
            onFocus: { appState.focusWalkthroughStep(step) }
        )
    }

    private func archivedStepRow(_ step: WalkthroughStep) -> some View {
        let disposition = appState.walkthroughDisposition(step)
        return HStack(spacing: 8) {
            Image(systemName: disposition == .completed ? "checkmark.circle.fill" : "forward.circle.fill")
                .foregroundStyle(disposition == .completed ? BG3Theme.success : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text("\(disposition == .completed ? "Done" : "Skipped") · \(step.area)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revisit") { appState.setWalkthroughDisposition(step, .pending) }
                .assistantActionButton().controlSize(.mini)
        }
        .padding(7).bg3InsetSurface(accent: disposition == .completed ? BG3Theme.success : .orange)
    }

    private func encounterBadge(_ encounter: StepEncounter) -> some View {
        let tint: Color = switch encounter {
        case .fight: Color(red: 0.92, green: 0.42, blue: 0.34)
        case .talk: Color(red: 0.55, green: 0.78, blue: 0.95)
        case .fightAndTalk: .orange
        case .explore, .pickup, .gate: BG3Theme.mutedParchment
        }
        return Label(encounter.label, systemImage: encounter.icon)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.7))
            .accessibilityLabel("Encounter type: \(encounter.label)")
    }

    @ViewBuilder
    private func routeStepDetail(_ step: WalkthroughStep) -> some View {
        let instructionLabel = step.decision == nil ? "DO" : "SAY"
        let instruction = step.decision?.recommended.label ?? step.summary
        let blockers = appState.walkthroughBlockers(step)
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(BG3Theme.bronze.opacity(0.35))
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(instructionLabel)
                    .font(.system(size: 9, weight: .heavy, design: .serif))
                    .foregroundStyle(BG3Theme.success)
                Text(instruction).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text(blockers.isEmpty ? "READY" : "BLOCKED")
                    .font(.system(size: 8.5, weight: .heavy, design: .serif))
                    .foregroundStyle(blockers.isEmpty ? BG3Theme.success : .orange)
            }
            if let blocker = blockers.first {
                Text("NEEDS • \(blocker)").font(.caption.bold()).foregroundStyle(.orange)
            }
            if !step.avoid.isEmpty {
                Text("AVOID • \(step.avoid)").font(.caption.bold()).foregroundStyle(.red)
            }
            if let outcome = appState.walkthroughOutcome(step) {
                Text("OUTCOME • \(outcome)").font(.caption.bold()).foregroundStyle(BG3Theme.success)
            }
            if let decision = step.decision, appState.walkthroughDisposition(step) != .completed {
                HStack(spacing: 6) {
                    outcomeButton(decision.recommended.label, recommended: true, step: step)
                    if !decision.alternatives.isEmpty {
                        Menu("Other outcome") {
                            ForEach(decision.alternatives, id: \.label) { option in
                                Button(option.label) { appState.resolveWalkthroughStep(step, outcome: option.label) }
                            }
                        }
                        .assistantActionButton().controlSize(.small)
                    }
                }
            }
            HStack(spacing: 7) {
                if step.decision == nil {
                    Button { appState.setWalkthroughDisposition(step, .completed) } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .assistantActionButton(accent: BG3Theme.success, prominent: true)
                }
                Button { appState.setWalkthroughDisposition(step, .skipped) } label: {
                    Label("Skip", systemImage: "forward.end")
                }
                .assistantActionButton()
                Button("Revisit") { appState.setWalkthroughDisposition(step, .pending) }
                    .assistantActionButton()
                Spacer()
            }
            .controlSize(.small)
            DisclosureGroup("More context") {
                VStack(alignment: .leading, spacing: 8) {
                    if step.decision != nil {
                        Text("DO • \(step.summary)").font(.caption)
                    }
                    if !step.rewards.isEmpty {
                        Text("POWER • \(step.rewards.joined(separator: " · "))")
                            .font(.caption.bold()).foregroundStyle(BG3Theme.gold)
                    }
                    if let decision = step.decision { decisionCard(decision) }
                    if let incident = appState.incidentProtocol(for: step) {
                        incidentProtocolCard(incident)
                    }
                    if let riskReward = step.riskReward { riskRewardCard(riskReward) }
                    if let source = URL(string: step.sourceUrl) {
                        Link("\(step.sourceLabel) ↗", destination: source).font(.caption2)
                    }
                }.padding(.top, 6)
            }
            .font(.caption)
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    private func outcomeButton(_ label: String, recommended: Bool, step: WalkthroughStep) -> some View {
        Button {
            appState.resolveWalkthroughStep(step, outcome: label)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: recommended ? "checkmark.circle.fill" : "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(label).font(.system(size: 10.5, weight: .semibold)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4).padding(.horizontal, 6)
        }
        .assistantActionButton(accent: recommended ? BG3Theme.success : BG3Theme.control, prominent: recommended)
        .controlSize(.small)
        .help(recommended ? "The guide's recommended outcome" : "The run went this way instead — later steps that assume the recommendation may not apply")
    }

    private func decisionCard(_ decision: WalkthroughDecision) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("CHOOSE").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
            Text(decision.prompt).font(.headline)
            tradeoffOption(decision.recommended, recommended: true)
            ForEach(decision.alternatives, id: \.label) { tradeoffOption($0, recommended: false) }
            Text(decision.reversible ? "Reversible" : "Irreversible")
                .font(.caption2.bold()).foregroundStyle(decision.reversible ? .green : .orange)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).bg3InsetSurface(accent: BG3Theme.gold)
    }

    private func tradeoffOption(_ option: DecisionOption, recommended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(recommended ? "RECOMMENDED" : "ALTERNATIVE") • \(option.label)")
                .font(.caption.bold()).foregroundStyle(recommended ? BG3Theme.success : BG3Theme.mutedParchment)
            if !option.benefits.isEmpty { Text("Preserves / gains • \(option.benefits.joined(separator: " · "))").font(.caption) }
            if !option.costs.isEmpty { Text("Costs / risks • \(option.costs.joined(separator: " · "))").font(.caption).foregroundStyle(.orange) }
        }
    }
}

// MARK: - Shared step cards
// Used by both RouteTabView (step detail) and OverlayView (current tab), so
// they live at file scope and take appState explicitly.

@MainActor
func incidentProtocolCard(_ incident: IncidentProtocol) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("RUN-ENDER PROTOCOL").font(.system(.caption, design: .serif).bold()).foregroundStyle(.red)
        Text("TRIGGER • \(incident.trigger)").font(.caption)
        ForEach(incident.safeActions, id: \.self) { Text("DO • \($0)").font(.caption).foregroundStyle(BG3Theme.success) }
        Text("NEVER • \(incident.never)").font(.caption.bold()).foregroundStyle(.red)
        Text("IF IT GOES WRONG • \(incident.escape)").font(.caption).foregroundStyle(.orange)
        if !incident.honorDelta.isEmpty {
            Text("HONOR DELTA • \(incident.honorDelta)").font(.caption).foregroundStyle(BG3Theme.gold)
        }
        if !incident.postFight.isEmpty {
            Divider().overlay(BG3Theme.bronze.opacity(0.4))
            Text("ENCOUNTER-SPECIFIC AFTERMATH").font(.caption.bold())
            ForEach(incident.postFight, id: \.self) { Text("□ \($0)").font(.caption) }
        }
        if let source = URL(string: incident.sourceUrl), !incident.sourceUrl.isEmpty {
            Link("\(incident.authority == "guide_fact" ? "Guide fact" : "Reviewed incident protocol") ↗", destination: source)
                .font(.caption2)
        }
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).bg3InsetSurface(accent: .red)
}

@MainActor
func riskRewardCard(_ riskReward: RiskReward) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("REWARD • \(riskReward.reward)").foregroundStyle(BG3Theme.success)
        Text("RISK • \(riskReward.risk)").foregroundStyle(.red)
        Text("SKIP • \(riskReward.skipCost)")
        Text("RETURN • \(riskReward.returnBy)").foregroundStyle(.secondary)
    }.font(.caption).padding(9).frame(maxWidth: .infinity, alignment: .leading).bg3InsetSurface(accent: BG3Theme.bronze)
}

private struct RouteRailRow: View {
    let step: WalkthroughStep
    let blockers: [String]
    let partyLevel: Int
    let isNext: Bool
    let isFocused: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onFocus: () -> Void
    @State private var hovered = false

    private var encounter: StepEncounter { StepEncounter.classify(step) }
    private var isUnderLevel: Bool { partyLevel < step.minimumLevel }
    private var detailLine: String {
        if let blocker = blockers.first { return "Needs: \(blocker)" }
        if let reward = step.rewards.first { return "\(reward) · \(step.area)" }
        return step.area
    }
    private var statusLine: String {
        if !blockers.isEmpty { return "BLOCKED" }
        return isUnderLevel ? "WAIT L\(step.minimumLevel)" : "L\(step.minimumLevel)+"
    }
    private var tint: Color {
        if !blockers.isEmpty { return .orange }
        switch encounter {
        case .fight: return Color(red: 0.92, green: 0.42, blue: 0.34)
        case .talk: return Color(red: 0.55, green: 0.78, blue: 0.95)
        case .fightAndTalk: return .orange
        case .explore, .pickup, .gate: return BG3Theme.mutedParchment
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: encounter.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(step.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            if isNext { Text("RECOMMENDED").railTag(BG3Theme.gold) }
                            if isFocused { Text("YOUR FOCUS").railTag(BG3Theme.success) }
                        }
                        Text(detailLine)
                            .font(.system(size: 9.5))
                            .foregroundStyle(blockers.isEmpty ? Color.secondary : Color.orange)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(statusLine)
                        .font(.system(size: 9, weight: .heavy, design: .serif))
                        .foregroundStyle(statusTint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(step.title), \(accessibilityStatus)")

            Button(action: onFocus) {
                Image(systemName: isFocused ? "scope" : "circle.dotted")
                    .font(.system(size: 12, weight: .bold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFocused ? BG3Theme.success : BG3Theme.gold)
            .help(isFocused ? "Current player focus" : "Focus \(step.title)")
            .accessibilityLabel(isFocused ? "Focused: \(step.title)" : "Focus \(step.title)")
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 8).fill(surfaceFill))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderTint, lineWidth: 0.7))
        .overlay(alignment: .leading) {
            if isFocused || isNext {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isFocused ? BG3Theme.success : BG3Theme.gold)
                    .frame(width: 3).padding(.vertical, 5)
            }
        }
        .onHover { hovered = $0 }
    }

    private var statusTint: Color {
        if !blockers.isEmpty || isUnderLevel { return .orange }
        return BG3Theme.mutedParchment
    }
    private var accessibilityStatus: String {
        blockers.first ?? (isUnderLevel ? "under level" : "eligible")
    }
    private var surfaceFill: Color {
        isSelected || hovered ? BG3Theme.bronze.opacity(0.24) : BG3Theme.ink.opacity(0.24)
    }
    private var borderTint: Color {
        isSelected ? BG3Theme.gold.opacity(0.65) : BG3Theme.bronze.opacity(0.32)
    }
}

private extension Text {
    func railTag(_ color: Color) -> some View {
        self
            .font(.system(size: 7.5, weight: .heavy, design: .serif))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
