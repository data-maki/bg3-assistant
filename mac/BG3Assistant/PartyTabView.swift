import SwiftUI

/// The planner's Party tab: party composition, levels, builds, and overrides.
struct PartyTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PARTY SETUP").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                            Text("Active four now · everyone else stays planned")
                                .font(.system(.headline, design: .serif))
                        }
                        Spacer()
                        Button("Open Loadout") { appState.plannerTab = .loadout }
                            .assistantGlassButton().tint(BG3Theme.bronzeBright).controlSize(.small)
                    }
                    HStack(spacing: 8) {
                        Text("Party level").font(.caption.bold()).foregroundStyle(BG3Theme.mutedParchment)
                        partyLevelSelector
                    }
                    Text("Quick level changes affect the active party only.").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)

                HStack {
                    Text("ACTIVE PARTY").font(.caption2.bold()).foregroundStyle(BG3Theme.gold)
                    Spacer()
                    Text("\(appState.activeParty.count) / 4").font(.caption.bold()).foregroundStyle(BG3Theme.mutedParchment)
                }.padding(.horizontal, 4)
                ForEach(appState.activeParty) { member in
                    RosterMemberEditor(
                        member: member,
                        builds: appState.builds,
                        onChange: { appState.updatePartyMember($0) },
                        onStatusChange: { _ = appState.setRosterStatus($0, for: member) }
                    )
                }

                DisclosureGroup("Camp & unavailable · \(inactiveRoster.count)") {
                    VStack(spacing: 4) {
                        ForEach(inactiveRoster) { member in
                            RosterMemberEditor(
                                member: member,
                                builds: appState.builds,
                                onChange: { appState.updatePartyMember($0) },
                                onStatusChange: { _ = appState.setRosterStatus($0, for: member) }
                            )
                        }
                    }.padding(.top, 5)
                }
                .font(.caption.bold())
                .padding(8)
                .bg3InsetSurface(accent: BG3Theme.bronze)

                if let karlach = appState.roster.first(where: { $0.name == "Karlach" }), karlach.rosterStatus == .dead {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("KARLACH OUTCOME").font(.caption2.bold()).foregroundStyle(.orange)
                        outcomeToggle("Killed for Mizora/Wyll path", key: "karlach_killed_for_robe")
                        outcomeToggle("Infernal Robe obtained", key: "infernal_robe_obtained")
                        Text("Death does not imply the robe was received.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(8).bg3InsetSurface(accent: .orange)
                }

                Toggle("Include camp builds in Loadout", isOn: Binding(
                    get: { appState.run.includeCampPlans ?? false },
                    set: { appState.setIncludeCampPlans($0) }
                ))
                .font(.caption)
                DisclosureGroup("Advanced class or capability overrides") {
                    VStack(spacing: 8) {
                        ForEach(appState.roster) { member in
                            PartyOverrideEditor(member: member, onChange: appState.updatePartyMember)
                        }
                    }.padding(.top, 7)
                }.font(.caption)
                Label(appState.mapDetectionStatus, systemImage: "map")
                    .font(.caption).foregroundStyle(appState.isMapOpen ? .green : .secondary)
            }.padding(.trailing, 8)
        }
        .alert(item: $appState.pendingRosterStatusChange) { pending in
            Alert(
                title: Text("Confirm \(pending.memberName) · \(pending.target == .dead ? "Dead" : "Departed")"),
                message: Text(pending.message),
                primaryButton: .destructive(Text(pending.target == .dead ? "Mark dead" : "Mark departed")) {
                    appState.confirmRosterStatusChange()
                },
                secondaryButton: .cancel {
                    appState.cancelRosterStatusChange()
                }
            )
        }
    }

    private var inactiveRoster: [PartyMember] {
        appState.roster.filter { $0.rosterStatus != .active }
    }

    private func outcomeToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { appState.run.storyOutcomes?.contains(key) == true },
            set: { appState.setStoryOutcome(key, confirmed: $0) }
        ))
        .font(.caption)
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
}

private struct RosterMemberEditor: View {
    let member: PartyMember
    let builds: [BuildSummary]
    let onChange: (PartyMember) -> Void
    let onStatusChange: (RosterStatus) -> Void

    private var isCustom: Bool { member.isCustom == true }
    private var selectedBuild: BuildSummary? { builds.first(where: { $0.id == member.buildId }) }
    private var currentBuildLevel: BuildLevel? { selectedBuild?.levels.last(where: { $0.level <= member.level }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(isCustom ? "CUSTOM CHARACTER" : member.name.uppercased(), systemImage: isCustom ? "person.crop.circle.badge.plus" : "person.2.fill")
                    .font(.caption2.bold()).foregroundStyle(isCustom ? BG3Theme.gold : BG3Theme.mutedParchment)
                Spacer()
                Text(selectedBuild?.role ?? member.className ?? "Unassigned")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 7) {
                if isCustom {
                    TextField("Character name", text: Binding(get: { member.name }, set: { var copy = member; copy.name = $0; onChange(copy) }))
                        .textFieldStyle(.roundedBorder).frame(width: 116)
                } else {
                    Text(member.name).font(.system(size: 12, weight: .semibold)).frame(width: 116, alignment: .leading)
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
                Picker("Status", selection: Binding(
                    get: { member.rosterStatus },
                    set: { status in onStatusChange(status) }
                )) {
                    ForEach(RosterStatus.allCases) { status in Text(statusLabel(status)).tag(status) }
                }
                .labelsHidden().frame(width: 82)
            }
            .controlSize(.small)
            if selectedBuild != nil, let current = currentBuildLevel {
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
            } else {
                Text("Pick a build to see this level's choices.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider() }
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

    private func statusLabel(_ status: RosterStatus) -> String {
        switch status {
        case .active: "Active"
        case .camp: "Camp"
        case .unrecruited: "Not met"
        case .unavailable: "Unavailable"
        case .dead: "Dead"
        case .departed: "Left"
        }
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
