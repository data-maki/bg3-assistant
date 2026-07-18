import SwiftUI

/// The planner's Now tab as a briefing: a scrolling body (what and why) over
/// a pinned action bar (how to resolve) that never moves. Three goal modes —
/// gear target, walkthrough step, fight checkpoint — share this one layout.
struct NowTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pathShowsAll = false

    var body: some View {
        Group {
            switch appState.currentGoal {
            case .target(let context):
                briefing { targetBody(context) } footer: { targetFooter(context) }
            case .laterAct:
                laterActBody
            case .step(let step):
                briefing { stepBody(step) } footer: { stepFooter(step) }
            case .checkpoint(let checkpoint):
                briefing { checkpointBody(checkpoint) } footer: { checkpointFooter }
            case .routeComplete:
                routeCompleteBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func briefing(
        @ViewBuilder _ content: () -> some View,
        @ViewBuilder footer: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
            }
            Divider().overlay(BG3Theme.bronze.opacity(0.38))
            footer()
                .padding(.top, 7)
        }
    }

    // MARK: - Walkthrough step mode

    private func stepBody(_ step: WalkthroughStep) -> some View {
        let encounter = StepEncounter.classify(step)
        let danger = appState.currentActivityDanger
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                StatusChip(text: encounter.label, tint: encounter.tint)
                StatusChip(text: "\(danger) risk", tint: BG3Theme.dangerColor(danger))
                StatusChip(text: "L\(step.minimumLevel)+", tint: BG3Theme.mutedParchment)
                Spacer()
                if appState.focusedWalkthroughStep?.id == step.id {
                    StatusChip(text: "your focus", tint: BG3Theme.success)
                }
            }
            Text(step.title)
                .font(BG3Type.pageTitle)
                .foregroundStyle(BG3Theme.parchment)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(step.phase) · \(step.area)")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)

            Divider().overlay(BG3Theme.bronze.opacity(0.38))

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
            if let outcome = appState.walkthroughOutcome(step) {
                FactRow(glyph: "✓", tint: BG3Theme.success, text: outcome)
            }
            stepMoreDisclosure(step)
        }
    }

    @ViewBuilder private func stepMoreDisclosure(_ step: WalkthroughStep) -> some View {
        let incident = appState.incidentProtocol(for: step)
        if step.decision != nil || !step.completionChecks.isEmpty || incident != nil || step.riskReward != nil || !step.sourceUrl.isEmpty {
            DisclosureGroup("More", isExpanded: $appState.moreContextExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    // Decision trade-offs live here, not in the main body: the
                    // focused view must fit without scrolling, and the pinned
                    // bar already carries the recommended outcome.
                    if let decision = step.decision {
                        DecisionCard(decision: decision, step: step, compactAlternatives: true)
                    }
                    if !step.completionChecks.isEmpty {
                        FactRow(glyph: "✓", tint: BG3Theme.success, text: "Done when: \(step.completionChecks.joined(separator: " · "))", secondary: true)
                    }
                    if let incident { incidentProtocolCard(incident) }
                    if let riskReward = step.riskReward { riskRewardCard(riskReward) }
                    if let source = URL(string: step.sourceUrl) {
                        Link("\(step.sourceLabel) ↗", destination: source).font(BG3Type.caption)
                    }
                }
                .padding(.top, 6)
            }
            .font(BG3Type.captionBold)
        }
    }

    @ViewBuilder private func stepFooter(_ step: WalkthroughStep) -> some View {
        HStack(spacing: 6) {
            if let decision = step.decision {
                Button {
                    appState.resolveWalkthroughStep(step, outcome: decision.recommended.label)
                } label: {
                    Label(decision.recommended.label, systemImage: "checkmark")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: true)
                .frame(maxWidth: .infinity, minHeight: 34)
                if !decision.alternatives.isEmpty {
                    WentDifferentlyMenu(step: step, decision: decision)
                        .frame(minHeight: 34)
                        .fixedSize()
                }
            } else {
                Button {
                    appState.completeCurrentActivity()
                } label: {
                    Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: true)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            Button {
                appState.skipCurrentActivity()
            } label: {
                Label("Skip", systemImage: "forward.end")
            }
            .assistantActionButton()
            .frame(minHeight: 34)
            .fixedSize()
        }
    }

    // MARK: - Checkpoint (fight) mode

    private func checkpointBody(_ checkpoint: RouteCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.run.selectedCheckpointId != nil, let reason = appState.routeRecommendationReason {
                HStack {
                    Label(reason, systemImage: "pin.fill").font(BG3Type.captionBold)
                    Spacer()
                    Button("Use recommended") { appState.followRecommendedRoute() }.controlSize(.mini)
                }
                .padding(7)
                .bg3InsetSurface(accent: BG3Theme.gold)
            }
            HStack(spacing: 5) {
                StatusChip(text: "fight", tint: BG3Theme.fightTint)
                StatusChip(text: "\(checkpoint.danger) risk", tint: BG3Theme.dangerColor(checkpoint.danger))
                StatusChip(text: "L\(checkpoint.minimumLevel)+", tint: BG3Theme.mutedParchment)
                Spacer()
            }
            Text(checkpoint.name)
                .font(BG3Type.pageTitle)
                .foregroundStyle(BG3Theme.parchment)
                .fixedSize(horizontal: false, vertical: true)
            Text(checkpoint.area)
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)

            Divider().overlay(BG3Theme.bronze.opacity(0.38))

            FactRow(glyph: "→", tint: BG3Theme.gold, text: checkpoint.advice)
            if let legendary = checkpoint.legendaryAction {
                FactRow(glyph: "⚠", tint: BG3Theme.warning, text: legendary)
            }
            if let failure = checkpoint.failureConditions.first {
                FactRow(glyph: "✕", tint: BG3Theme.danger, text: failure)
            }
            checkpointMoreDisclosure(checkpoint)
        }
    }

    private func checkpointMoreDisclosure(_ checkpoint: RouteCheckpoint) -> some View {
        DisclosureGroup("More", isExpanded: $appState.moreContextExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !checkpoint.honorDecisions.isEmpty {
                    ForEach(checkpoint.honorDecisions, id: \.text) { decision in
                        FactRow(glyph: "⑂", tint: BG3Theme.gold, text: decision.text, secondary: true)
                    }
                }
                if !checkpoint.enemies.isEmpty {
                    FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: "Enemies: \(checkpoint.enemies)", secondary: true)
                }
                ForEach(checkpoint.failureConditions.dropFirst(), id: \.self) { failure in
                    FactRow(glyph: "✕", tint: BG3Theme.danger, text: failure, secondary: true)
                }
                ForEach(checkpoint.irreversibleWarnings, id: \.self) { warning in
                    FactRow(glyph: "⚠", tint: BG3Theme.warning, text: warning, secondary: true)
                }
                ForEach(checkpoint.notes, id: \.self) { note in
                    FactRow(glyph: "★", tint: BG3Theme.gold, text: note, secondary: true)
                }
                HStack(spacing: 6) {
                    TextField("Skip note (optional)", text: $appState.skipNoteDraft)
                        .textFieldStyle(.plain)
                        .font(BG3Type.body)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(BG3Theme.ink.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BG3Theme.bronze.opacity(0.4), lineWidth: 0.7))
                    Button("Pin tactics") { appState.pinCurrentFight() }
                        .assistantActionButton()
                        .disabled(appState.readiness?.status == "blocked")
                }
                if let sourceURL = URL(string: checkpoint.source.url) {
                    Link("Guide source ↗", destination: sourceURL).font(BG3Type.caption)
                }
            }
            .padding(.top, 6)
        }
        .font(BG3Type.captionBold)
    }

    private var checkpointFooter: some View {
        HStack(spacing: 6) {
            Button {
                appState.requestDisposition(.completed)
            } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .assistantActionButton(accent: BG3Theme.success, prominent: true)
            .frame(maxWidth: .infinity, minHeight: 34)
            Button {
                appState.requestDisposition(.skipped)
            } label: {
                Label("Skip", systemImage: "forward.end")
            }
            .assistantActionButton()
            .frame(minHeight: 34)
            .fixedSize()
        }
    }

    // MARK: - Gear target mode

    private func targetBody(_ context: GearTargetContext) -> some View {
        let path = appState.gearTargetPath
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                StatusChip(text: "target", tint: BG3Theme.gold, filled: true)
                StatusChip(text: context.gear.priority.lowercased(), tint: BG3Theme.mutedParchment)
                Spacer()
            }
            HStack(alignment: .center, spacing: 9) {
                GearItemIcon(gear: context.gear, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Get \(context.gear.item)")
                        .font(BG3Type.pageTitle)
                        .foregroundStyle(BG3Theme.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("for \(context.member.name) · \(context.gear.region)")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                }
            }

            Divider().overlay(BG3Theme.bronze.opacity(0.38))

            if let effect = context.gear.effect, !effect.isEmpty {
                FactRow(glyph: "★", tint: BG3Theme.gold, text: effect)
            }
            if !context.gear.why.isEmpty {
                FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: context.gear.why, secondary: true)
            }
            if let conflict = appState.gearConflict(for: context.gear, member: context.member) {
                FactRow(glyph: "⚠", tint: BG3Theme.warning, text: conflict.short, secondary: true)
            }
            pathSection(path)
        }
    }

    @ViewBuilder private func pathSection(_ path: [GearLogic.PathRow]) -> some View {
        let remaining = path.filter { row in
            switch row {
            case .levelGate: true
            case .step(_, let done): !done
            case .info, .acquisition: false
            }
        }.count
        let stepCount = path.filter { if case .step = $0 { true } else { false } }.count
        VStack(alignment: .leading, spacing: 5) {
            Text(stepCount > 0 ? "Path · \(remaining) of \(stepCount + (path.contains { if case .levelGate = $0 { true } else { false } } ? 1 : 0)) remain" : "Path")
                .font(BG3Type.overline)
                .foregroundStyle(BG3Theme.gold)
            let visible = pathShowsAll ? path : Array(path.prefix(4))
            ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                pathRow(row)
            }
            if path.count > 4, !pathShowsAll {
                Button("· \(path.count - 4) more") { pathShowsAll = true }
                    .buttonStyle(.plain)
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.gold)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    @ViewBuilder private func pathRow(_ row: GearLogic.PathRow) -> some View {
        switch row {
        case .levelGate(let required, let partyLevel):
            FactRow(glyph: "◇", tint: BG3Theme.caution, text: "Reach level \(required) (\(partyLevel) now)")
        case .step(let step, let done):
            HStack(spacing: 7) {
                Button {
                    appState.setWalkthroughDisposition(step, done ? .pending : .completed)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(done ? BG3Theme.success : BG3Theme.mutedParchment)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(done ? "Mark not done" : "Mark done")
                Text(step.title)
                    .font(BG3Type.body)
                    .foregroundStyle(done ? BG3Theme.mutedParchment : BG3Theme.parchment)
                    .strikethrough(done, color: BG3Theme.mutedParchment)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    appState.plannerTab = .route
                } label: {
                    Text("route ›").font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold)
                }
                .buttonStyle(.plain)
                .help("Show this step on the route")
            }
        case .info(let text):
            FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: text, secondary: true)
        case .acquisition(let text):
            FactRow(glyph: "→", tint: BG3Theme.gold, text: text)
        }
    }

    private func targetFooter(_ context: GearTargetContext) -> some View {
        HStack(spacing: 6) {
            Button {
                appState.completeGearTarget()
            } label: {
                Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .assistantActionButton(accent: BG3Theme.success, prominent: true)
            .frame(maxWidth: .infinity, minHeight: 34)
            if context.gear.isMapObjective, let buildId = context.member.buildId {
                Button {
                    appState.openCurrentActMap(buildId: buildId, item: context.gear.item, level: context.member.level)
                } label: {
                    Label("Map", systemImage: "mappin.and.ellipse")
                }
                .assistantActionButton()
                .frame(minHeight: 34)
                .fixedSize()
            }
            Button {
                appState.clearGearTarget()
            } label: {
                Label("Clear target", systemImage: "xmark")
            }
            .assistantActionButton()
            .frame(minHeight: 34)
            .fixedSize()
        }
    }

    // MARK: - Later acts / route complete

    private var laterActBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.currentActGuide?.title ?? "Act \(appState.selectedAct)")
                .font(BG3Type.pageTitle)
            if appState.activeGuideLoaded {
                Label("Act \(appState.selectedAct) equipment and map references are loaded.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(BG3Theme.success)
                Label("Step-by-step route guidance is not available for this act yet.", systemImage: "clock")
                    .foregroundStyle(BG3Theme.warning)
            } else {
                Label(appState.statusMessage, systemImage: "arrow.clockwise")
                    .foregroundStyle(BG3Theme.warning)
            }
            HStack(spacing: 6) {
                Button("Review loadouts") { appState.plannerTab = .loadout }
                Button("Open map") { appState.openCurrentActMap() }
                Button("Act gate") { appState.plannerTab = .act }
            }
            .assistantActionButton()
        }
        .font(BG3Type.body)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var routeCompleteBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.routeHasConsequentialSkips
                ? "Act \(appState.selectedAct) resolved with skips"
                : "Act \(appState.selectedAct) route complete")
                .font(BG3Type.pageTitle)
            if appState.routeHasConsequentialSkips {
                Label("Revisit required or recommended skipped steps before treating this route as complete.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BG3Theme.warning)
            } else if appState.selectedAct == 3 {
                Label("The final reviewed route is resolved.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(BG3Theme.success)
            } else if appState.currentActRouteConsequences.isEmpty {
                Label("Nothing missable remains in the reviewed route. Act \(appState.selectedAct + 1) is safe to enter.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(BG3Theme.success)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Finish these before Act \(appState.selectedAct + 1)")
                        .font(BG3Type.rowTitle)
                    ForEach(appState.currentActRouteConsequences, id: \.self) { blocker in
                        FactRow(glyph: "⚠", tint: BG3Theme.warning, text: blocker)
                    }
                }
            }
        }
        .font(BG3Type.body)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}
