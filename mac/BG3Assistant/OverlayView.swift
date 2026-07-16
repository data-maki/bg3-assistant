import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.overlayExpanded { planner }
            else { PeekCardView() }
        }
        .padding(8)
        .confirmationDialog(
            appState.confirmationMessage ?? "Confirm progress",
            isPresented: Binding(
                get: { appState.pendingDisposition != nil },
                set: { if !$0 { appState.cancelPendingDisposition() } }
            )
        ) {
            if appState.pendingDisposition == .skipped {
                Button("Skip Anyway", role: .destructive, action: appState.confirmPendingDisposition)
            } else {
                Button("Mark Done", action: appState.confirmPendingDisposition)
            }
            Button("Cancel", role: .cancel, action: appState.cancelPendingDisposition)
        }
        .alert("Attach a BG3 screenshot?", isPresented: $appState.showScreenRecordingPermissionPrompt) {
            Button("Continue", action: appState.requestScreenRecordingPermission)
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Chat can capture the current BG3 window once and attach it to your next message. It excludes the overlay and is sent to OpenRouter only when you send.")
        }
    }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var expandedContentSize: CGSize {
        let panel = OverlayMetrics.expandedSize(
            for: referenceFrame,
            tab: appState.plannerTab,
            moreContextExpanded: appState.moreContextExpanded
        )
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var plannerNavigation: some View {
        HStack(spacing: 2) {
            ForEach(PlannerTab.primary) { tab in
                let selected = appState.plannerTab == tab
                Button {
                    appState.plannerTab = tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: selected ? .bold : .semibold, design: .serif))
                        .foregroundStyle(selected ? BG3Theme.parchment : BG3Theme.mutedParchment)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(BG3Theme.bronze.opacity(0.22))
                                    .overlay(Capsule().stroke(BG3Theme.bronzeBright.opacity(0.52), lineWidth: 0.7))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityValue(selected ? "Selected" : "")
            }
        }
        .padding(3)
        .background(BG3Theme.ink.opacity(0.52), in: Capsule())
        .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.52), lineWidth: 0.7))
    }

    private var planner: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                PetSpriteView(size: 42)
                DraggableArea {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plannerTitle)
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment).lineLimit(1)
                            if appState.plannerTab != .settings,
                               appState.currentWalkthroughStep != nil || appState.currentCheckpoint != nil {
                                Text("\(appState.currentActivityArea) • L\(appState.currentActivityMinimumLevel)+ • \(appState.currentActivityLabel.lowercased())")
                                    .font(.caption2).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 38)
                }
                .fixedSize(horizontal: false, vertical: true)
                Button { appState.openActOneMap() } label: {
                    Image(systemName: "map").frame(width: 18, height: 18)
                }
                .assistantActionButton()
                .help("Open Act 1 map")
                Button(action: appState.openChat) {
                    Image(systemName: "bubble.left.and.bubble.right").frame(width: 18, height: 18)
                }
                .assistantActionButton(accent: appState.plannerTab == .chat ? BG3Theme.bronzeBright : BG3Theme.control)
                .help("Ask about this run")
                Button(action: appState.openSettings) {
                    Image(systemName: "gearshape").frame(width: 18, height: 18)
                }
                .assistantActionButton(accent: appState.plannerTab == .settings ? BG3Theme.bronzeBright : BG3Theme.control)
                .help("Settings")
                Button(action: appState.togglePlanner) {
                    Image(systemName: "xmark").frame(width: 18, height: 18)
                }
                .assistantActionButton()
                .help("Close planner")
            }
            .fixedSize(horizontal: false, vertical: true)
            plannerNavigation

            if let notice = appState.guideUpdateNotice {
                Label(notice, systemImage: "pin.fill").font(.caption).foregroundStyle(.orange)
            }

            Group {
                switch appState.plannerTab {
                case .current: currentTab
                case .route: RouteTabView()
                case .party: PartyTabView()
                case .chat: ChatTabView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(width: expandedContentSize.width, height: expandedContentSize.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.control)
        .assistantGlassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.46), radius: 20, y: 8)
    }

    private var plannerTitle: String {
        switch appState.plannerTab {
        case .chat: "Ask about this run"
        case .settings: "Settings"
        default: appState.currentActivityTitle
        }
    }

    @ViewBuilder private var currentTab: some View {
        if let checkpoint = appState.currentCheckpoint {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if appState.run.selectedCheckpointId != nil, let reason = appState.routeRecommendationReason {
                        HStack {
                            Label(reason, systemImage: "pin.fill").font(.caption.bold())
                            Spacer()
                            Button("Use recommended") { appState.followRecommendedRoute() }.controlSize(.mini)
                        }
                        .padding(8).bg3InsetSurface(accent: BG3Theme.gold)
                    }
                    encounterHUD(checkpoint)

                    HStack(spacing: 7) {
                        Button { appState.requestDisposition(.completed) } label: {
                            Label("Mark done", systemImage: "checkmark")
                        }
                        .assistantActionButton(accent: BG3Theme.success, prominent: true)
                        Button { appState.requestDisposition(.skipped) } label: {
                            Label("Skip", systemImage: "forward.end")
                        }
                        .assistantActionButton()
                        Spacer()
                        Button { appState.plannerTab = .route } label: {
                            Label("Route", systemImage: "list.bullet")
                        }
                        .assistantActionButton()
                    }

                    DisclosureGroup("More context", isExpanded: $appState.moreContextExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let legendary = checkpoint.legendaryAction {
                                Text("HONOR ACTION • \(legendary)").font(.caption).foregroundStyle(.orange)
                            }
                            if !checkpoint.honorDecisions.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("CHOICES").font(.caption.bold()).foregroundStyle(BG3Theme.gold)
                                    ForEach(checkpoint.honorDecisions, id: \.text) { decision in
                                        Text(decision.text).font(.caption)
                                    }
                                }
                            }
                            factSection("Enemies", text: checkpoint.enemies)
                            listSection("All failure conditions", checkpoint.failureConditions, icon: "xmark.octagon.fill", color: .red)
                            listSection("Irreversible / time-sensitive", checkpoint.irreversibleWarnings, icon: "clock.badge.exclamationmark", color: .orange)
                            listSection("Quests and pickups", checkpoint.notes, icon: "bag.fill", color: BG3Theme.gold)
                            HStack {
                                TextField("Skip note (optional)", text: $appState.skipNoteDraft).textFieldStyle(.roundedBorder)
                                Button("Pin tactics") { appState.pinCurrentFight() }
                                    .disabled(appState.readiness?.status == "blocked")
                                Button("Revisit") { appState.requestDisposition(.pending) }
                            }
                            if let sourceURL = URL(string: checkpoint.source.url) {
                                Link("Guide source • \(checkpoint.source.sheet), row \(checkpoint.source.row) ↗", destination: sourceURL)
                                    .font(.caption)
                            }
                        }.padding(.top, 8)
                    }
                    .font(.caption)
                }
                .padding(.trailing, 8)
            }
        } else if appState.currentWalkthroughStep != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    walkthroughNowCard
                }.padding(.trailing, 8)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                walkthroughNowCard
                Text(appState.route.isEmpty ? "Guide offline" : "Act 1 route complete").font(.title.bold())
                if appState.route.isEmpty {
                    Label("The local guide service is unavailable. Quit and reopen the assistant.", systemImage: "wifi.exclamationmark").foregroundStyle(.red)
                } else if appState.actTwoBlockers.isEmpty {
                    Label("Nothing missable left — Act 2 is safe to enter.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    listSection("Finish these before Act 2", appState.actTwoBlockers, icon: "exclamationmark.triangle.fill", color: .orange)
                }
            }
        }
    }

    @ViewBuilder private var walkthroughNowCard: some View {
        if let step = appState.currentWalkthroughStep {
            let status = appState.walkthroughDisposition(step)
            let instructionLabel = step.decision == nil ? "DO" : "SAY"
            let instruction = step.decision?.recommended.label ?? step.summary
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("\(appState.focusedWalkthroughStep?.id == step.id ? "YOUR FOCUS" : appState.currentActivityLabel)")
                        .font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                    Spacer()
                    Text("L\(step.minimumLevel)+ • \(step.phase)").font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(instructionLabel) • \(instruction)").font(.system(size: 12, weight: .semibold))
                if !step.avoid.isEmpty {
                    Text("AVOID • \(step.avoid)").font(.caption.bold()).foregroundStyle(.red)
                }
                if let outcome = appState.walkthroughOutcome(step) {
                    Text("OUTCOME • \(outcome)").font(.caption.bold()).foregroundStyle(BG3Theme.success)
                }
                HStack(spacing: 6) {
                    if let decision = step.decision, status != .completed {
                        Button {
                            appState.resolveWalkthroughStep(step, outcome: decision.recommended.label)
                        } label: {
                            Label(decision.recommended.label, systemImage: "checkmark")
                        }
                        .assistantActionButton(accent: BG3Theme.success, prominent: true)
                        if !decision.alternatives.isEmpty {
                            Menu("Other outcome") {
                                ForEach(decision.alternatives, id: \.label) { option in
                                    Button(option.label) { appState.resolveWalkthroughStep(step, outcome: option.label) }
                                }
                            }
                            .assistantActionButton()
                        }
                    } else if status != .completed {
                        Button { appState.completeCurrentActivity() } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .assistantActionButton(accent: BG3Theme.success, prominent: true)
                    }
                    Button { appState.skipCurrentActivity() } label: {
                        Label("Skip", systemImage: "forward.end")
                    }
                    .assistantActionButton()
                    if status != .pending {
                        Button("Revisit") { appState.revisitCurrentActivity() }
                            .assistantActionButton()
                    }
                    Spacer()
                    Button { appState.plannerTab = .route } label: {
                        Label("Route", systemImage: "list.bullet")
                    }
                    .assistantActionButton()
                }
                DisclosureGroup("More context", isExpanded: $appState.moreContextExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        if step.decision != nil {
                            Text("DO • \(step.summary)").font(.caption)
                        }
                        if !step.rewards.isEmpty {
                            Text("POWER • \(step.rewards.joined(separator: " · "))")
                                .font(.caption.bold()).foregroundStyle(BG3Theme.gold)
                        }
                        if let incident = appState.incidentProtocol(for: step) {
                            incidentProtocolCard(incident)
                        }
                        if let riskReward = step.riskReward {
                            riskRewardCard(riskReward)
                        }
                    }.padding(.top, 6)
                }
                .font(.caption)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .bg3InsetSurface(accent: step.kind == "dialogue" || step.kind == "decision" ? BG3Theme.gold : BG3Theme.bronze)
        }
    }

    private func encounterHUD(_ checkpoint: RouteCheckpoint) -> some View {
        let danger = checkpoint.legendaryAction
            ?? checkpoint.failureConditions.dropFirst().first
            ?? checkpoint.enemies
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label("DANGER", systemImage: "exclamationmark.shield.fill")
                    .font(.system(.caption, design: .serif).bold())
                    .foregroundStyle(BG3Theme.dangerColor(checkpoint.danger))
                Spacer()
                Text("FIGHT • L\(checkpoint.minimumLevel)+")
                    .font(.caption2.bold())
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            Text(danger)
                .font(.system(size: 12, weight: .semibold))

            Divider().overlay(BG3Theme.bronze.opacity(0.38))

            if let failure = checkpoint.failureConditions.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVOID")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text(failure).font(.system(size: 12, weight: .semibold))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DO")
                    .font(.caption.bold())
                    .foregroundStyle(BG3Theme.gold)
                Text(checkpoint.advice)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BG3Theme.dangerColor(checkpoint.danger).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .bg3InsetSurface(accent: BG3Theme.dangerColor(checkpoint.danger))
    }

    @ViewBuilder private var levelPlanCard: some View {
        if let plan = appState.levelActivityPlan {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PARTY L\(appState.lowestPartyLevel) • \(plan.activityLabel)")
                        .font(.caption.bold()).foregroundStyle(BG3Theme.gold)
                    Spacer()
                    Text(plan.phaseName).font(.caption).foregroundStyle(.secondary)
                }
                Text("Do next: \(plan.recommendation.name)").font(.headline)
                if plan.safeXP.isEmpty {
                    Text("No safe fights at this level — earn XP from quests and dialogue instead.")
                        .font(.caption)
                } else {
                    Text("Safe fights now: \(plan.safeXP.prefix(3).map { "\($0.name) (L\($0.minimumLevel))" }.joined(separator: " • "))")
                        .font(.caption)
                }
                if let core = plan.coreChallenge {
                    Text("Next main fight: \(core.name) • L\(core.minimumLevel)+")
                        .font(.caption.bold())
                }
                Text(plan.gateAdvice).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).bg3InsetSurface(accent: BG3Theme.gold)
        }
    }

    private func factSection(_ title: String, text: String, color: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(text).font(.system(size: 12)).textSelection(.enabled) }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading).bg3InsetSurface(accent: color)
    }

    private func listSection(_ title: String, _ items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            if items.isEmpty { Text("No guide fact recorded.").font(.caption).foregroundStyle(.secondary) }
            ForEach(items, id: \.self) { Label($0, systemImage: icon).font(.system(size: 12)).foregroundStyle(color == .secondary ? .primary : color) }
        }
    }

}
