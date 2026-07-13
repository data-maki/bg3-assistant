import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var speech = SpeechInputService()

    var body: some View {
        Group {
            if appState.overlayExpanded { planner }
            else { peekCard }
        }
        .padding(8)
        .confirmationDialog(
            appState.confirmationMessage ?? "Confirm progress",
            isPresented: Binding(
                get: { appState.pendingDisposition != nil },
                set: { if !$0 { appState.cancelPendingDisposition() } }
            )
        ) {
            Button("Confirm", role: .destructive, action: appState.confirmPendingDisposition)
            Button("Cancel", role: .cancel, action: appState.cancelPendingDisposition)
        }
    }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var collapsedContentSize: CGSize {
        let panel = OverlayMetrics.collapsedSize(for: referenceFrame)
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var expandedContentSize: CGSize {
        let panel = OverlayMetrics.expandedSize(for: referenceFrame, tab: appState.plannerTab)
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var peekCard: some View {
        let size = collapsedContentSize
        return VStack(spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(BG3Theme.ink.opacity(0.76))
                    Circle().stroke(BG3Theme.bronze, lineWidth: 2)
                    Circle().inset(by: 3).stroke(BG3Theme.gold.opacity(0.48), lineWidth: 0.7)
                    PetSpriteView(size: 55)
                }
                .frame(width: 64, height: 64)

                DraggableArea {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(appState.combatCardPinned ? "PINNED" : (appState.levelActivityPlan?.activityLabel ?? "NEXT"))
                                .font(.system(size: 8.5, weight: .heavy, design: .serif))
                                .foregroundStyle(BG3Theme.gold)
                            Spacer(minLength: 4)
                            if let checkpoint = appState.currentCheckpoint {
                                Text("L\(checkpoint.minimumLevel)+ · \(checkpoint.danger.uppercased())")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(dangerColor(checkpoint.danger))
                            }
                        }
                    if let checkpoint = appState.currentCheckpoint {
                        Text(checkpoint.name)
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment)
                                .lineLimit(1)
                            Text("AVOID · \(checkpoint.failureConditions.first ?? checkpoint.advice)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(BG3Theme.mutedParchment)
                                .lineLimit(2)
                    } else {
                        Text(appState.route.isEmpty ? "Guide offline — open the app" : "Act 1 complete")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                shortcut("Plan", icon: "list.clipboard.fill", action: appState.showPlannerNow)
                shortcut("Ask", icon: "bubble.left.and.text.bubble.right.fill", action: appState.openChat)
                shortcut("Done", icon: "checkmark.seal.fill", disabled: appState.currentCheckpoint == nil, tint: BG3Theme.success) {
                    appState.requestDisposition(.completed)
                }
            }
        }
        .padding(9).frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.gold)
        .assistantGlassSurface(cornerRadius: 14)
        .shadow(color: .black.opacity(0.42), radius: 14, y: 6)
        .contextMenu {
            Button("Open chat", action: appState.openChat)
            Button("Snooze warnings 10 minutes", action: appState.snoozeWarnings)
            Button(appState.isCurrentCheckpointMuted ? "Unmute checkpoint" : "Mute checkpoint", action: appState.toggleMuteCurrentCheckpoint)
            if appState.combatCardPinned { Button("Unpin fight", action: appState.unpinFight) }
        }
        .accessibilityElement(children: .contain)
    }

    private func shortcut(_ title: String, icon: String, disabled: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .serif))
            }
            .foregroundStyle(BG3Theme.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .assistantGlassButton()
        .controlSize(.mini)
        .tint(tint ?? BG3Theme.bronzeBright)
        .disabled(disabled)
        .accessibilityLabel(title)
    }

    private var plannerNavigation: some View {
        HStack(spacing: 2) {
            ForEach(PlannerTab.allCases) { tab in
                let selected = appState.plannerTab == tab
                Button {
                    appState.plannerTab = tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: selected ? .bold : .semibold, design: .serif))
                        .foregroundStyle(selected ? BG3Theme.gold : BG3Theme.mutedParchment)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(BG3Theme.bronze.opacity(0.36))
                                    .overlay(Capsule().stroke(BG3Theme.gold.opacity(0.46), lineWidth: 0.7))
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
                            Text(appState.currentCheckpoint?.name ?? "Act 1 route reviewed")
                                .font(.system(size: 14, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment).lineLimit(1)
                            if let checkpoint = appState.currentCheckpoint {
                                Text("\(checkpoint.area) • L\(checkpoint.minimumLevel)+ • \(checkpoint.danger) danger")
                                    .font(.caption2).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 38)
                }
                .fixedSize(horizontal: false, vertical: true)
                Button(action: appState.togglePlanner) {
                    Image(systemName: "xmark").frame(width: 18, height: 18)
                }
                .assistantGlassButton()
                .tint(BG3Theme.bronzeBright)
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
                case .route: routeTab
                case .party: partyTab
                case .chat: chatTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(width: expandedContentSize.width, height: expandedContentSize.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.gold)
        .assistantGlassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.46), radius: 20, y: 8)
    }

    @ViewBuilder private var currentTab: some View {
        if let checkpoint = appState.currentCheckpoint {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DO NOW").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                            Text(appState.levelActivityPlan?.recommendation.name ?? checkpoint.name)
                                .font(.system(.title2, design: .serif).bold())
                            Text(appState.levelActivityPlan?.gateAdvice ?? checkpoint.area)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
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
                        Text("DON'T DIE").font(.caption.bold()).foregroundStyle(dangerColor(checkpoint.danger))
                        Text(checkpoint.advice).font(.system(size: 12, weight: .semibold))
                        if let failure = checkpoint.failureConditions.first {
                            Text("Avoid: \(failure)").font(.caption).foregroundStyle(.red)
                        }
                        if let legendary = checkpoint.legendaryAction {
                            Text("Legendary: \(legendary)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(dangerColor(checkpoint.danger).opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    .bg3InsetSurface(accent: dangerColor(checkpoint.danger))
                    if !checkpoint.honorDecisions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHOOSE").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                            ForEach(checkpoint.honorDecisions, id: \.text) { decision in
                                Text(decision.text).font(.system(size: 12))
                            }
                        }
                        .padding(9).bg3InsetSurface(accent: BG3Theme.gold)
                    }
                    checklist("PREP", checkpoint.preparation, checked: appState.currentProgress.checkedPreparation, action: appState.togglePreparation)

                    HStack {
                        Button("Pin fight") { appState.pinCurrentFight() }
                            .assistantGlassButton()
                            .disabled(appState.readiness?.status == "blocked")
                        Button("Done") { appState.requestDisposition(.completed) }
                            .assistantGlassButton().tint(BG3Theme.success)
                        Button("Revisit") { appState.requestDisposition(.pending) }
                            .assistantGlassButton()
                        Spacer()
                    }

                    DisclosureGroup("Fight details, completion, and sources") {
                        VStack(alignment: .leading, spacing: 10) {
                            factSection("Enemies", text: checkpoint.enemies)
                            listSection("All failure conditions", checkpoint.failureConditions, icon: "xmark.octagon.fill", color: .red)
                            listSection("Irreversible / time-sensitive", checkpoint.irreversibleWarnings, icon: "clock.badge.exclamationmark", color: .orange)
                            listSection("Quests and pickups", checkpoint.notes, icon: "bag.fill", color: BG3Theme.gold)
                            checklist("Completion", checkpoint.completionChecks, checked: appState.currentProgress.checkedCompletion, action: appState.toggleCompletion)
                            HStack {
                                TextField("Skip note (optional)", text: $appState.skipNoteDraft).textFieldStyle(.roundedBorder)
                                Button("Skip") { appState.requestDisposition(.skipped) }
                                Button("Check screen") { Task { await appState.checkScreen() } }
                                    .disabled(appState.isLoading || !appState.gameDetected)
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
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(appState.route.isEmpty ? "Guide offline" : "Act 1 route complete").font(.title.bold())
                if appState.route.isEmpty {
                    Label("Open the control window and press Start Backend to load the guide.", systemImage: "wifi.exclamationmark").foregroundStyle(.red)
                } else if appState.actTwoBlockers.isEmpty {
                    Label("Nothing missable left — Act 2 is safe to enter.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    listSection("Finish these before Act 2", appState.actTwoBlockers, icon: "exclamationmark.triangle.fill", color: .orange)
                }
            }
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

    private var routeTab: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Act 1 route").font(.headline)
                        Text("Ordered for your level, one region at a time.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Follow recommended") { appState.followRecommendedRoute() }
                }
                .padding(9).bg3InsetSurface(accent: BG3Theme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Before you leave for Act 2").font(.headline)
                    if appState.actTwoBlockers.isEmpty {
                        Label("Nothing missable left — Act 2 is safe", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        ForEach(appState.actTwoBlockers.prefix(3), id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) }
                        if appState.actTwoBlockers.count > 3 {
                            Text("+ \(appState.actTwoBlockers.count - 3) more").font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                ForEach(appState.route) { checkpoint in
                    let state = appState.run.progress[checkpoint.id]?.disposition ?? .pending
                    Button { appState.selectCheckpoint(checkpoint) } label: {
                        HStack {
                            Image(systemName: state == .completed ? "checkmark.circle.fill" : state == .skipped ? "forward.circle.fill" : "circle")
                                .foregroundStyle(state == .completed ? .green : state == .skipped ? .orange : .secondary)
                            Text("\(checkpoint.routeOrder)").font(.caption.monospaced()).frame(width: 22)
                            VStack(alignment: .leading) {
                                Text(checkpoint.name).font(.system(size: 13, weight: .semibold))
                                Text("\(checkpoint.area) • L\(checkpoint.minimumLevel)+ • \(checkpoint.region)").font(.caption).foregroundStyle(.secondary)
                                if state == .skipped, let note = appState.run.progress[checkpoint.id]?.skipNote, !note.isEmpty {
                                    Text("Skip note: \(note)").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Circle().fill(dangerColor(checkpoint.danger)).frame(width: 8, height: 8)
                        }
                        .padding(8).bg3InsetSurface(accent: BG3Theme.bronze)
                    }.buttonStyle(.plain)
                }
            }.padding(.trailing, 8)
        }
    }

    private var partyTab: some View {
        let selectedStoryNames = Set(appState.run.party.dropFirst().map(\.name))
        return ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PARTY SETUP").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                            Text("One custom character + three story companions")
                                .font(.system(.headline, design: .serif))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("LOADOUT ACT").font(.caption2.bold()).foregroundStyle(BG3Theme.mutedParchment)
                            actSelector
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Party level").font(.caption.bold()).foregroundStyle(BG3Theme.mutedParchment)
                        partyLevelSelector
                    }
                    Text("Set everyone at once, then adjust individual levels below.").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
                ForEach(Array(appState.run.party.enumerated()), id: \.element.id) { index, member in
                    PartyMemberEditor(
                        member: member,
                        slotNumber: index,
                        builds: appState.builds,
                        selectedAct: appState.selectedAct,
                        unavailableStoryNames: selectedStoryNames.subtracting([member.name]),
                        onChange: appState.updatePartyMember,
                        onOpenMap: { buildId, item, _ in
                            appState.openActOneMap(buildId: buildId, item: item, level: appState.lowestPartyLevel)
                        }
                    )
                }
                DisclosureGroup("Advanced class or capability overrides") {
                    VStack(spacing: 8) {
                        ForEach(appState.run.party) { member in
                            PartyOverrideEditor(member: member, onChange: appState.updatePartyMember)
                        }
                    }.padding(.top, 7)
                }.font(.caption)
                Label(appState.mapDetectionStatus, systemImage: "map")
                    .font(.caption).foregroundStyle(appState.isMapOpen ? .green : .secondary)
            }.padding(.trailing, 8)
        }
    }

    private var actSelector: some View {
        Picker("Act", selection: Binding(
            get: { appState.selectedAct },
            set: { act in appState.setSelectedAct(act) }
        )) {
            ForEach(1...3, id: \.self) { act in Text("Act \(act)").tag(act) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 164)
        .controlSize(.small)
        .accessibilityLabel("Loadout act")
    }

    private var partyLevelSelector: some View {
        HStack(spacing: 2) {
            ForEach(1...7, id: \.self) { level in
                let selected = appState.lowestPartyLevel == level
                Button {
                    appState.setAllPartyLevels(level)
                } label: {
                    Text("L\(level)")
                        .font(.system(size: 9.5, weight: selected ? .bold : .medium, design: .serif))
                        .foregroundStyle(selected ? BG3Theme.gold : BG3Theme.mutedParchment)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(BG3Theme.bronze.opacity(0.40))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(BG3Theme.gold.opacity(0.45), lineWidth: 0.7))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set party level \(level)")
                .accessibilityValue(selected ? "Selected" : "")
            }
        }
        .padding(3)
        .background(BG3Theme.ink.opacity(0.50), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(BG3Theme.bronze.opacity(0.46), lineWidth: 0.7))
    }

    private var chatTab: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if appState.chatLines.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.system(size: 26)).foregroundStyle(.secondary)
                                Text("Ask anything about the current checkpoint.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Answers come from the reviewed guide — it says so when it doesn't know.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 36)
                        }
                        ForEach(appState.chatLines) { line in
                            ChatBubble(line: line).id(line.id)
                        }
                        if let response = appState.latestResponse, !response.candidates.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Screen evidence", systemImage: "camera.viewfinder").font(.caption.bold())
                                Text(response.screenSummary).font(.caption)
                                ForEach(response.candidates) { candidate in
                                    Button("Use \(candidate.checkpointId) (\(Int(candidate.confidence * 100))%)") {
                                        appState.confirmScreenCandidate(candidate)
                                    }.controlSize(.small)
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            .bg3InsetSurface(accent: BG3Theme.gold)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: appState.chatLines.count) { _, _ in
                    if let last = appState.chatLines.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 6) {
                quickPrompt("What's next?")
                quickPrompt("How do I not die here?")
                quickPrompt("Is my party ready?")
                Spacer()
                Button { Task { await appState.checkScreen() } } label: {
                    Label("Scan screen", systemImage: "camera.viewfinder").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderless).disabled(appState.isLoading || !appState.gameDetected)
            }

            HStack(spacing: 7) {
                Button(action: speech.toggle) {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(speech.isRecording ? .red : .secondary)
                        .frame(width: 26, height: 26)
                        .background(speech.isRecording ? AnyShapeStyle(.red.opacity(0.18)) : AnyShapeStyle(BG3Theme.ink.opacity(0.56)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(speech.isRecording ? "Stop dictation" : "Dictate your question")
                TextField(speech.isRecording ? "Listening…" : "Ask about this checkpoint…", text: $appState.chatDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { Task { await appState.sendChat() } }
                Button {
                    Task { await appState.sendChat() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.5) : BG3Theme.gold)
                }
                .buttonStyle(.plain)
                .disabled(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(BG3Theme.ink.opacity(0.54))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke((speech.isRecording ? Color.red : BG3Theme.bronze).opacity(speech.isRecording ? 0.5 : 0.45)))

            if let error = speech.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
        .onChange(of: speech.transcript) { _, transcript in
            if !transcript.isEmpty { appState.chatDraft = transcript }
        }
    }

    private func quickPrompt(_ text: String) -> some View {
        Button(text) { Task { await appState.sendChat(text) } }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(BG3Theme.ink.opacity(0.50)).clipShape(Capsule())
            .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.36), lineWidth: 0.7))
    }

    private func levelBadge(_ checkpoint: RouteCheckpoint) -> some View {
        VStack { Text("MIN").font(.caption2); Text("L\(checkpoint.minimumLevel)").font(.title3.bold()) }
            .padding(8)
            .background(dangerColor(checkpoint.danger).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
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

    private func dangerColor(_ danger: String) -> Color {
        danger == "extreme" ? .red : danger == "high" ? .orange : danger == "medium" ? .yellow : .cyan
    }
}

private struct ChatBubble: View {
    let line: ChatLine

    private var isUser: Bool { line.role == "You" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            Text(line.text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(isUser ? AnyShapeStyle(BG3Theme.bronze.opacity(0.78)) : AnyShapeStyle(BG3Theme.ink.opacity(0.58)))
                .foregroundStyle(BG3Theme.parchment)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            if !isUser { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct PartyMemberEditor: View {
    let member: PartyMember
    let slotNumber: Int
    let builds: [BuildSummary]
    let selectedAct: Int
    let unavailableStoryNames: Set<String>
    let onChange: (PartyMember) -> Void
    let onOpenMap: (String, String?, Int) -> Void

    private var isCustom: Bool { slotNumber == 0 }
    private var selectedBuild: BuildSummary? { builds.first(where: { $0.id == member.buildId }) }
    private var currentBuildLevel: BuildLevel? { selectedBuild?.levels.last(where: { $0.level <= member.level }) }
    private var actGear: [BuildGear] {
        selectedBuild?.gear
            .filter { $0.act == selectedAct }
            .sorted { gearRank($0.priority) < gearRank($1.priority) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(isCustom ? "CUSTOM CHARACTER" : "STORY COMPANION \(slotNumber)", systemImage: isCustom ? "person.crop.circle.badge.plus" : "person.2.fill")
                    .font(.caption2.bold()).foregroundStyle(isCustom ? BG3Theme.gold : BG3Theme.mutedParchment)
                Spacer()
                if let className = member.className, !className.isEmpty {
                    Text(className).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 7) {
                if isCustom {
                    TextField("Character name", text: Binding(get: { member.name }, set: { var copy = member; copy.name = $0; onChange(copy) }))
                        .textFieldStyle(.roundedBorder).frame(width: 116)
                } else {
                    Picker("Companion", selection: Binding(get: { member.name }, set: { updateStoryCompanion($0) })) {
                        if !StoryCompanion.actOne.contains(where: { $0.name == member.name }) {
                            Text(member.name).tag(member.name)
                        }
                        ForEach(StoryCompanion.actOne) { companion in
                            Text(companion.name).tag(companion.name)
                                .disabled(unavailableStoryNames.contains(companion.name))
                        }
                    }
                    .labelsHidden().frame(width: 116)
                }
                Picker("Level", selection: Binding(get: { member.level }, set: { level in
                    var copy = member
                    copy.level = level
                    if let build = builds.first(where: { $0.id == copy.buildId }),
                       let plan = build.levels.last(where: { $0.level <= level }) {
                        copy.className = plan.take
                    }
                    onChange(copy)
                })) {
                    ForEach(1...12, id: \.self) { Text("L\($0)").tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 58)
                Picker("Build", selection: Binding(get: { member.buildId ?? "" }, set: { updateBuild($0) })) {
                    Text("Choose reviewed build").tag("")
                    ForEach(builds) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            if let build = selectedBuild, let current = currentBuildLevel {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("DO NOW").font(.caption2.bold()).foregroundStyle(BG3Theme.gold)
                        Text("L\(member.level) · \(current.take)")
                            .font(.caption.bold()).foregroundStyle(BG3Theme.parchment)
                        if !current.subclassChoice.isEmpty, current.subclassChoice != "-" {
                            Text("· \(current.subclassChoice)").font(.caption2).foregroundStyle(BG3Theme.mutedParchment)
                        }
                    }
                    if !current.choices.isEmpty, current.choices != "-" {
                        Text(current.choices).font(.caption2).foregroundStyle(BG3Theme.parchment)
                    }
                    if !current.tactics.isEmpty, current.tactics != "-" {
                        Label(current.tactics, systemImage: "sparkles")
                            .font(.caption2).foregroundStyle(BG3Theme.success)
                    }
                }
                actLoadout(build: build)
            } else {
                Text("Pick a build to see this level's choices and gear.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func actLoadout(build: BuildSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ACT \(selectedAct) LOADOUT")
                    .font(.caption2.bold()).foregroundStyle(BG3Theme.gold)
                Text("\(actGear.count) reviewed")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if selectedAct == 1, !actGear.isEmpty {
                    Button("Open build map") { onOpenMap(build.id, nil, member.level) }
                        .buttonStyle(.plain).font(.caption2.bold()).foregroundStyle(BG3Theme.bronzeBright)
                }
            }
            if actGear.isEmpty {
                Text("No reviewed Act \(selectedAct) equipment for this build yet.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(actGear.prefix(3))) { gear in gearRow(gear, buildId: build.id) }
                if actGear.count > 3 {
                    DisclosureGroup("\(actGear.count - 3) more Act \(selectedAct) items") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(actGear.dropFirst(3))) { gear in gearRow(gear, buildId: build.id) }
                        }.padding(.top, 4)
                    }
                    .font(.caption2.bold())
                }
            }
            if selectedAct != 1, !actGear.isEmpty {
                Label("The map covers Act 1 only — use the notes above to find Act \(selectedAct) items.", systemImage: "map")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(7)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func gearRow(_ gear: BuildGear, buildId: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption2).foregroundStyle(BG3Theme.bronzeBright).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(gear.item).font(.caption.bold()).foregroundStyle(BG3Theme.parchment)
                Text("\(gear.priority) · \(gear.slot) · \(gear.region)")
                    .font(.caption2).foregroundStyle(BG3Theme.gold)
                Text(gear.acquisition).font(.caption2).foregroundStyle(BG3Theme.mutedParchment).lineLimit(2)
            }
            Spacer(minLength: 4)
            if selectedAct == 1 {
                Button { onOpenMap(buildId, gear.item, member.level) } label: {
                    Label("Map", systemImage: "mappin.and.ellipse").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain).font(.caption2.bold()).foregroundStyle(BG3Theme.bronzeBright)
                .help(gear.why)
            }
        }
    }

    private func gearRank(_ priority: String) -> Int {
        ["Required", "Core", "Upgrade", "Starter", "Support", "Defence", "Supply", "Optional", "Endgame"]
            .firstIndex(of: priority) ?? 99
    }

    private func updateStoryCompanion(_ name: String) {
        guard !unavailableStoryNames.contains(name) else { return }
        var copy = member
        copy.name = name
        if copy.buildId == nil, let companion = StoryCompanion.actOne.first(where: { $0.name == name }) {
            copy.className = companion.defaultClass
        }
        onChange(copy)
    }

    private func updateBuild(_ buildId: String) {
        var copy = member
        copy.buildId = buildId.isEmpty ? nil : buildId
        if let build = builds.first(where: { $0.id == buildId }),
           let plan = build.levels.last(where: { $0.level <= copy.level }) {
            copy.className = plan.take
        } else if !isCustom, let companion = StoryCompanion.actOne.first(where: { $0.name == copy.name }) {
            copy.className = companion.defaultClass
        }
        onChange(copy)
    }
}

private struct PartyOverrideEditor: View {
    let member: PartyMember
    let onChange: (PartyMember) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.name).font(.caption.bold())
            HStack {
                TextField("Class override", text: Binding(get: { member.className ?? "" }, set: { value in
                    var copy = member
                    copy.className = value.isEmpty ? nil : value
                    onChange(copy)
                }))
                TextField("Extra capabilities, comma-separated", text: Binding(
                    get: { member.preparedTags.joined(separator: ", ") },
                    set: { value in
                        var copy = member
                        copy.preparedTags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        onChange(copy)
                    }
                ))
            }.textFieldStyle(.roundedBorder)
        }
    }
}
