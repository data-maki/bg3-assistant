import SwiftUI

struct ManualBuildPlannerView: View {
    @EnvironmentObject private var appState: AppState
    let memberID: String
    let onBack: () -> Void

    @State private var expandedLevel: Int?
    @State private var multiclassLevel: Int?

    private var member: PartyMember? { appState.roster.first { $0.id == memberID } }

    var body: some View {
        if let member {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(action: onBack) {
                        Label("Character", systemImage: "chevron.left").font(BG3Type.captionBold)
                    }
                    .assistantActionButton()
                    .controlSize(.small)
                    Spacer()
                    StatusChip(text: appState.runDifficulty.title.uppercased(), tint: BG3Theme.gold)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        buildHeader(member)
                        abilityEditor(member)
                        levelTimeline(member)
                    }
                    .padding(.trailing, 7)
                }
            }
            .onAppear {
                appState.beginManualBuild(for: member)
                expandedLevel = max(1, min(member.level, 12))
            }
        } else {
            Text("This party member is no longer in the run.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
        }
    }

    private func buildHeader(_ member: PartyMember) -> some View {
        let plan = member.manualBuild ?? .empty(name: "\(member.name)'s Build", scores: member.effectiveAbilityScores)
        return VStack(alignment: .leading, spacing: 6) {
            Text("MANUAL BUILD")
                .font(BG3Type.overline)
                .foregroundStyle(BG3Theme.gold)
            TextField(
                "Build name",
                text: Binding(
                    get: { plan.name },
                    set: { appState.renameManualBuild($0, for: member) }
                )
            )
            .textFieldStyle(.roundedBorder)
            Text(plan.classSummary.isEmpty ? "Choose a class at Level 1 to begin." : plan.classSummary)
                .font(BG3Type.captionBold)
                .foregroundStyle(plan.classSummary.isEmpty ? BG3Theme.warning : BG3Theme.parchment)
            Text("Each new level continues your current class automatically. Use Multiclass only when you want the next level—and following levels—to use a different class.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

    private func abilityEditor(_ member: PartyMember) -> some View {
        let scores = member.manualBuild?.abilityScores ?? member.effectiveAbilityScores
        let spent = AbilityProgression.pointBuyCost(scores)
        let valid = spent >= 0 && spent <= 27
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("ABILITY POINTS")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                StatusChip(
                    text: spent < 0 ? "8–15 EACH" : "\(spent)/27 SPENT",
                    tint: valid ? BG3Theme.success : BG3Theme.warning,
                    filled: spent == 27
                )
            }
            HStack(spacing: 5) {
                ForEach(Ability.allCases) { ability in
                    VStack(spacing: 3) {
                        Text(ability.shortName)
                            .font(BG3Type.captionBold)
                            .foregroundStyle(BG3Theme.gold)
                        Button {
                            appState.setManualAbility(
                                ability,
                                value: max(8, ability.value(in: scores) - 1),
                                for: member
                            )
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.plain)
                        .disabled(ability.value(in: scores) <= 8)
                        Text("\(ability.value(in: scores))")
                            .font(BG3Type.pageTitle)
                            .foregroundStyle(BG3Theme.parchment)
                        Button {
                            appState.setManualAbility(
                                ability,
                                value: min(15, ability.value(in: scores) + 1),
                                for: member
                            )
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .disabled(ability.value(in: scores) >= 15)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(BG3Theme.ink.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(ability.displayName) \(ability.value(in: scores))")
                }
            }
            Text(spent == 27
                ? "Valid 27-point base distribution. Apply BG3's +2 and +1 bonuses in character creation."
                : "Spend exactly 27 points, then apply BG3's separate +2 and +1 bonuses in game.")
                .font(BG3Type.caption)
                .foregroundStyle(spent == 27 ? BG3Theme.success : BG3Theme.mutedParchment)
        }
        .padding(10)
        .bg3InsetSurface(accent: spent == 27 ? BG3Theme.success : BG3Theme.bronze)
    }

    private func levelTimeline(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LEVELS 1–12")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("Current L\(member.level)")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            ForEach(1...12, id: \.self) { level in
                levelCard(level, member: member)
            }
        }
    }

    private func levelCard(_ level: Int, member: PartyMember) -> some View {
        let plan = member.manualBuild ?? .empty(name: "", scores: member.effectiveAbilityScores)
        let saved = plan.levels.first { $0.characterLevel == level }
        let selectedClass = saved?.className ?? ""
        let classLevel = plan.classLevel(at: level)
        let definition = BG3ClassCatalog.definition(named: selectedClass)
        let levelDefinition = definition?.levels[classLevel]
        let isExpanded = expandedLevel == level
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    expandedLevel = isExpanded ? nil : level
                    if isExpanded { multiclassLevel = nil }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(level)")
                        .font(BG3Type.pageTitle)
                        .foregroundStyle(BG3Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(level <= member.level ? BG3Theme.gold : BG3Theme.bronzeBright, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedClass.isEmpty ? "Choose class" : "\(selectedClass) \(classLevel)")
                            .font(BG3Type.rowTitle)
                            .foregroundStyle(BG3Theme.parchment)
                        Text(levelSummary(levelDefinition, saved: saved))
                            .font(BG3Type.caption)
                            .foregroundStyle(BG3Theme.mutedParchment)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(BG3Theme.gold)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if level == 1 || selectedClass.isEmpty {
                    Picker(
                        level == 1 ? "Starting class" : "Class at character level \(level)",
                        selection: Binding(
                            get: { selectedClass },
                            set: { appState.setManualClass($0, at: level, for: member) }
                        )
                    ) {
                        Text("Choose class…").tag("")
                        ForEach(availableClasses(for: plan)) { definition in
                            Label(definition.name, systemImage: definition.systemImage).tag(definition.name)
                        }
                    }
                    .controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        Label("Continuing as \(selectedClass)", systemImage: definition?.systemImage ?? "shield.fill")
                            .font(BG3Type.captionBold)
                            .foregroundStyle(BG3Theme.parchment)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                multiclassLevel = multiclassLevel == level ? nil : level
                            }
                        } label: {
                            Label("Multiclass", systemImage: "arrow.triangle.branch")
                        }
                        .assistantActionButton()
                        .controlSize(.small)
                        .accessibilityHint("Choose a different class beginning at character level \(level)")
                    }
                    .padding(7)
                    .background(BG3Theme.ink.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))

                    if multiclassLevel == level {
                        Picker(
                            "New class at character level \(level)",
                            selection: Binding(
                                get: { "" },
                                set: { newClass in
                                    guard !newClass.isEmpty else { return }
                                    appState.setManualClass(newClass, at: level, for: member)
                                    multiclassLevel = nil
                                }
                            )
                        ) {
                            Text("Choose a different class…").tag("")
                            ForEach(availableClasses(for: plan).filter { $0.name != selectedClass }) { definition in
                                Label(definition.name, systemImage: definition.systemImage).tag(definition.name)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                if let levelDefinition {
                    if !levelDefinition.features.isEmpty {
                        Text("GAINED")
                            .font(BG3Type.overline)
                            .foregroundStyle(BG3Theme.mutedParchment)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(levelDefinition.features) { option in
                                optionTile(option, selected: true, action: nil)
                            }
                        }
                    }
                    ForEach(levelDefinition.choices.filter {
                        choiceIsAvailable($0, plan: plan, saved: saved)
                    }) { group in
                        choiceGroup(group, saved: saved, level: level, member: member)
                    }
                }
            }
        }
        .padding(9)
        .bg3InsetSurface(accent: selectedClass.isEmpty ? BG3Theme.bronze : BG3Theme.gold)
    }

    private func choiceGroup(
        _ group: BG3BuildChoiceGroup,
        saved: ManualBuildLevel?,
        level: Int,
        member: PartyMember
    ) -> some View {
        let selected = Set(saved?.selections[group.id] ?? [])
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(group.title.uppercased())
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("\(selected.count)/\(group.maximumSelections)")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(selected.count == group.maximumSelections ? BG3Theme.success : BG3Theme.warning)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(group.options) { option in
                    optionTile(option, selected: selected.contains(option.name)) {
                        appState.toggleManualChoice(option.name, in: group, at: level, for: member)
                    }
                }
            }
        }
    }

    @ViewBuilder private func optionTile(
        _ option: BG3BuildOption,
        selected: Bool,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(spacing: 7) {
            BG3ChoiceIcon(option: option, selected: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(option.name)
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.parchment)
                    .lineLimit(2)
                Text(option.detail)
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(BG3Theme.ink.opacity(selected ? 0.58 : 0.32), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? BG3Theme.gold.opacity(0.75) : BG3Theme.bronze.opacity(0.28), lineWidth: 0.8)
        )
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityValue(selected ? "Selected" : "Not selected")
        } else {
            content
        }
    }

    private func levelSummary(_ definition: BG3ClassLevelDefinition?, saved: ManualBuildLevel?) -> String {
        guard let definition else { return "No choices recorded" }
        let gained = definition.features.map(\.name)
        let selected = saved?.selections.values.flatMap { $0 } ?? []
        let summary = gained + selected
        return summary.isEmpty ? "No new selection at this class level" : summary.joined(separator: " · ")
    }

    private func availableClasses(for plan: ManualBuildPlan) -> [BG3ClassDefinition] {
        guard appState.runDifficulty == .explorer,
              let first = plan.levels.first?.className,
              !first.isEmpty else { return BG3ClassCatalog.definitions }
        return BG3ClassCatalog.definitions.filter { $0.name == first }
    }

    private func choiceIsAvailable(
        _ group: BG3BuildChoiceGroup,
        plan: ManualBuildPlan,
        saved: ManualBuildLevel?
    ) -> Bool {
        guard let requirement = group.requiredSelection else { return true }
        if group.requiresSelectionAtSameLevel {
            return saved?.selections.values.contains { $0.contains(requirement) } == true
        }
        return plan.levels.contains { level in
            level.selections.values.contains { $0.contains(requirement) }
        }
    }
}
