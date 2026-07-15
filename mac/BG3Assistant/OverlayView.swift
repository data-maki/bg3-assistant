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
        let panel = OverlayMetrics.expandedSize(for: referenceFrame, tab: appState.plannerTab)
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
                            Text(appState.plannerTab == .chat ? "Ask about this run" : appState.currentActivityTitle)
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment).lineLimit(1)
                            if appState.currentWalkthroughStep != nil || appState.currentCheckpoint != nil {
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

    @ViewBuilder private var currentTab: some View {
        if let checkpoint = appState.currentCheckpoint {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    runResumeLine
                    HStack(alignment: .firstTextBaseline) {
                        Text("FIGHT").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                        Spacer()
                        levelBadge(checkpoint)
                    }
                    if appState.run.selectedCheckpointId != nil, let reason = appState.routeRecommendationReason {
                        HStack {
                            Label(reason, systemImage: "pin.fill").font(.caption.bold())
                            Spacer()
                            Button("Use recommended") { appState.followRecommendedRoute() }.controlSize(.mini)
                        }
                        .padding(8).bg3InsetSurface(accent: BG3Theme.gold)
                    }
                    readinessCard
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DO • \(checkpoint.advice)")
                            .font(.system(size: 12, weight: .semibold)).lineLimit(3)
                        if let failure = checkpoint.failureConditions.first {
                            Text("AVOID • \(failure)").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(BG3Theme.dangerColor(checkpoint.danger).opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    .bg3InsetSurface(accent: BG3Theme.dangerColor(checkpoint.danger))
                    compactPreparation(checkpoint)

                    HStack(spacing: 7) {
                        Button { appState.requestDisposition(.completed) } label: {
                            Label("Done", systemImage: "checkmark")
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

                    DisclosureGroup("More context") {
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
                            checklist("All preparation", checkpoint.preparation, checked: appState.currentProgress.checkedPreparation, action: appState.togglePreparation)
                            factSection("Enemies", text: checkpoint.enemies)
                            listSection("All failure conditions", checkpoint.failureConditions, icon: "xmark.octagon.fill", color: .red)
                            listSection("Irreversible / time-sensitive", checkpoint.irreversibleWarnings, icon: "clock.badge.exclamationmark", color: .orange)
                            listSection("Quests and pickups", checkpoint.notes, icon: "bag.fill", color: BG3Theme.gold)
                            checklist("Completion", checkpoint.completionChecks, checked: appState.currentProgress.checkedCompletion, action: appState.toggleCompletion)
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
                    runResumeLine
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

    private var runResumeLine: some View {
        HStack(spacing: 6) {
            Label("\(appState.remainingCount) active", systemImage: "arrow.forward.circle.fill")
            Text("·")
            Label("\(appState.archivedCount) archived", systemImage: "archivebox.fill")
            Spacer()
            Text("Manual progress")
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(BG3Theme.mutedParchment)
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
                DisclosureGroup("More context") {
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

    private var readinessCard: some View {
        let readiness = appState.readiness
        let color: Color = readiness?.status == "blocked" || readiness?.status == "danger" ? .red : readiness?.status == "caution" ? .orange : .green
        let blockers = readiness?.blockers ?? []
        let warnings = readiness?.warnings ?? []
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label((readiness?.status ?? "checking").uppercased(), systemImage: readiness?.status == "ready" ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.subheadline.bold()).foregroundStyle(color)
                Spacer()
                Text("Party level \(appState.lowestPartyLevel)").font(.caption.bold())
            }
            ForEach(blockers.prefix(1), id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            ForEach(warnings.prefix(blockers.isEmpty ? 1 : 0), id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if blockers.isEmpty, warnings.isEmpty, let next = readiness?.nextActions.first {
                Text(next).font(.caption)
            }
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .bg3InsetSurface(accent: color)
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

    private func levelBadge(_ checkpoint: RouteCheckpoint) -> some View {
        VStack { Text("MIN").font(.caption2); Text("L\(checkpoint.minimumLevel)").font(.title3.bold()) }
            .padding(8)
            .background(BG3Theme.dangerColor(checkpoint.danger).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BG3Theme.bronze.opacity(0.45), lineWidth: 0.7))
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

    private func compactPreparation(_ checkpoint: RouteCheckpoint) -> some View {
        let checked = appState.currentProgress.checkedPreparation
        let confirmed = checkpoint.preparation.filter(checked.contains).count
        let remaining = checkpoint.preparation.filter { !checked.contains($0) }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("PREP").font(.caption.bold()).foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("\(confirmed)/\(checkpoint.preparation.count)").font(.caption2.bold()).foregroundStyle(.secondary)
            }
            if remaining.isEmpty {
                Label("Ready to start", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(BG3Theme.success)
            } else {
                ForEach(Array(remaining.prefix(2)), id: \.self) { item in
                    Button { appState.togglePreparation(item) } label: {
                        Label(item, systemImage: "square").font(.system(size: 12)).lineLimit(2)
                    }.buttonStyle(.plain)
                }
                if remaining.count > 2 {
                    Text("+\(remaining.count - 2) in More context")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: remaining.isEmpty ? BG3Theme.success : BG3Theme.gold)
    }

    private func checklist(_ title: String, _ items: [String], checked: Set<String>, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Label(item, systemImage: checked.contains(item) ? "checkmark.square.fill" : "square").font(.system(size: 12))
                }.buttonStyle(.plain)
            }
        }
    }
}
