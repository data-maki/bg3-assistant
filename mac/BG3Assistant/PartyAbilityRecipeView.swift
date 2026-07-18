import SwiftUI

struct PartyAbilityRecipeView: View {
    @EnvironmentObject private var appState: AppState
    let memberID: String
    let onBack: () -> Void

    @State private var selectedSetupID: String?
    @State private var pendingUniqueSourceID: String?

    private var member: PartyMember? { appState.roster.first { $0.id == memberID } }
    private var build: BuildSummary? {
        guard let id = member?.buildId else { return nil }
        return appState.builds.first { $0.id == id }
    }
    private var activeSetup: AbilitySetupPlan? {
        guard let member else { return nil }
        return AbilityProgression.activeSetup(in: build, at: member.level)
    }
    private var selectedSetup: AbilitySetupPlan? {
        guard let selectedSetupID else { return activeSetup }
        return build?.abilitySetups?.first { $0.id == selectedSetupID } ?? activeSetup
    }

    var body: some View {
        if let member {
            content(member)
                .onAppear { selectedSetupID = activeSetup?.id }
                .onChange(of: activeSetup?.id) { _, value in selectedSetupID = value }
                .confirmationDialog(
                    "Move this unique reward?",
                    isPresented: Binding(
                        get: { pendingUniqueSourceID != nil },
                        set: { if !$0 { pendingUniqueSourceID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Move reward to \(member.name)") {
                        guard let id = pendingUniqueSourceID,
                              let source = build?.abilitySources?.first(where: { $0.id == id }) else { return }
                        appState.setAbilitySource(source, applied: true, for: member)
                        pendingUniqueSourceID = nil
                    }
                    Button("Cancel", role: .cancel) { pendingUniqueSourceID = nil }
                } message: {
                    Text("A once-per-run reward can be assigned to only one party member. Its previous assignment will be removed.")
                }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                backButton
                Text("This party member is no longer in the run.")
                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                Spacer()
            }
        }
    }

    private func content(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                backButton
                Spacer()
                Text(member.name).font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold).lineLimit(1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let setup = selectedSetup {
                        setupTimeline(member)
                        setupRecipe(setup, member: member)
                    } else {
                        missingRecipe
                    }
                    currentScores(member)
                    sourceLedger(member)
                }
                .padding(.trailing, 6)
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Character", systemImage: "chevron.left").font(BG3Type.captionBold)
        }
        .assistantActionButton()
        .controlSize(.small)
    }

    @ViewBuilder private func setupTimeline(_ member: PartyMember) -> some View {
        if let setups = build?.abilitySetups, setups.count > 1 {
            VStack(alignment: .leading, spacing: 5) {
                Text("SETUP TIMELINE").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                HStack(spacing: 5) {
                    ForEach(setups) { setup in
                        let selected = setup.id == selectedSetup?.id
                        let available = setup.level <= member.level
                        Button {
                            selectedSetupID = setup.id
                        } label: {
                            VStack(spacing: 1) {
                                Text(setup.level == 1 ? "START" : "L\(setup.level)")
                                    .font(BG3Type.captionBold)
                                Text(setup.firstClass)
                                    .font(BG3Type.caption).lineLimit(1)
                            }
                            .foregroundStyle(selected ? BG3Theme.parchment : BG3Theme.mutedParchment)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .background((selected ? BG3Theme.bronze : BG3Theme.ink).opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? BG3Theme.gold.opacity(0.7) : BG3Theme.bronze.opacity(0.3), lineWidth: 0.8))
                        .opacity(available ? 1 : 0.62)
                        .accessibilityValue(selected ? "Selected" : available ? "Available" : "Future setup")
                    }
                }
            }
        }
    }

    private func setupRecipe(_ setup: AbilitySetupPlan, member: PartyMember) -> some View {
        let cost = AbilityProgression.pointBuyCost(setup.pointBuyScores)
        let valid = AbilityProgression.isValidBG3Setup(setup)
        let isCurrent = setup.id == activeSetup?.id
        let applied = member.appliedAbilitySetupId == setup.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(setup.label.uppercased())
                        .font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                    Text(isCurrent ? "Enter these values in BG3 now" : "Reference setup")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                }
                Spacer()
                StatusChip(text: valid ? "\(cost)/27 VALID" : "INVALID", tint: valid ? BG3Theme.success : BG3Theme.danger, filled: valid)
            }

            PartyAbilityTable(setup: setup)

            FactRow(glyph: "1", tint: BG3Theme.gold, text: "First class: \(setup.firstClass)")
            FactRow(glyph: "2", tint: BG3Theme.gold, text: setup.classOrder, secondary: true)
            FactRow(glyph: "◆", tint: BG3Theme.success, text: setup.reason, secondary: true)

            if isCurrent {
                Button {
                    appState.applyAbilitySetup(setup, to: member)
                } label: {
                    Label(applied ? "Recorded in BG3" : "Mark these values applied in BG3", systemImage: applied ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: !applied)
                .disabled(applied || !valid)
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: applied ? BG3Theme.success : BG3Theme.gold)
    }

    private var missingRecipe: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No validated Ability Points recipe", systemImage: "exclamationmark.triangle.fill")
                .font(BG3Type.rowTitle).foregroundStyle(BG3Theme.warning)
            Text("This imported or unassigned build does not specify point buy and the separate +2/+1 bonuses. Its final scores are not enough to reconstruct one authoritative setup.")
                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.warning)
    }

    private func currentScores(_ member: PartyMember) -> some View {
        let equipped = appState.equippedItemKeys(for: member)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECORDED NOW / BUILD GOAL").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("Modifier in parentheses").font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            }
            HStack(spacing: 5) {
                ForEach(Ability.allCases) { ability in
                    let score = AbilityProgression.breakdown(for: member, build: build, ability: ability, equippedItemKeys: equipped)
                    VStack(spacing: 2) {
                        Text(ability.shortName).font(BG3Type.captionBold).foregroundStyle(BG3Theme.mutedParchment)
                        Text("\(score.current)").font(BG3Type.rowTitle).foregroundStyle(BG3Theme.parchment)
                        Text("\(signed(AbilityProgression.modifier(for: score.current))) / \(score.target)")
                            .font(BG3Type.caption).foregroundStyle(score.current >= score.target ? BG3Theme.success : BG3Theme.gold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(BG3Theme.ink.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ability.displayName), recorded score \(score.current), modifier \(signed(AbilityProgression.modifier(for: score.current))), build goal \(score.target)")
                }
            }
            if let note = build?.targetAbilityNote, !note.isEmpty {
                Text(note).font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func sourceLedger(_ member: PartyMember) -> some View {
        let sources = build?.abilitySources ?? []
        return VStack(alignment: .leading, spacing: 7) {
            Text("WHERE EVERY BOOST COMES FROM")
                .font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
            if sources.isEmpty {
                Text("This setup reaches its reviewed goal without additional recorded ability sources.")
                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            } else {
                ForEach(sources) { source in sourceRow(source, member: member) }
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func sourceRow(_ source: AbilityPlanSource, member: PartyMember) -> some View {
        let applied = appState.abilitySourceIsApplied(source, to: member)
        let owner = appState.abilitySourceOwner(source)
        let future = member.level < source.minimumLevel
        return HStack(alignment: .top, spacing: 8) {
            Text(source.ability.shortName)
                .font(BG3Type.captionBold).foregroundStyle(BG3Theme.ink)
                .frame(width: 30, height: 24)
                .background(sourceColor(source.kind), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(source.label).font(BG3Type.captionBold).foregroundStyle(BG3Theme.parchment)
                    Text(sourceEffect(source)).font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold)
                }
                Text("\(source.kind.label) · \(sourceTiming(source))")
                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                if !source.note.isEmpty {
                    Text(source.note).font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 2)
            sourceAction(source, member: member, applied: applied, owner: owner, future: future)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func sourceAction(
        _ source: AbilityPlanSource,
        member: PartyMember,
        applied: Bool,
        owner: PartyMember?,
        future: Bool
    ) -> some View {
        switch source.kind {
        case .asi, .feat:
            StatusChip(text: future ? "L\(source.minimumLevel)" : "PLANNED", tint: future ? BG3Theme.control : BG3Theme.success)
        case .equipment:
            if applied {
                StatusChip(text: "EQUIPPED", tint: BG3Theme.success, filled: true)
            } else if let owner, owner.id != member.id {
                Text("Used by \(owner.name)").font(BG3Type.captionBold).foregroundStyle(BG3Theme.warning).lineLimit(2)
            } else {
                Button("Loadout") { appState.plannerTab = .loadout }
                    .assistantActionButton(accent: BG3Theme.gold)
                    .controlSize(.small)
            }
        case .permanent, .consumable:
            if applied {
                Button("Recorded") { appState.setAbilitySource(source, applied: false, for: member) }
                    .assistantActionButton(accent: BG3Theme.success, prominent: true)
                    .controlSize(.small)
            } else {
                Button(owner == nil || owner?.id == member.id ? "Record" : "Move") {
                    if source.uniqueAcrossParty, let owner, owner.id != member.id {
                        pendingUniqueSourceID = source.id
                    } else {
                        appState.setAbilitySource(source, applied: true, for: member)
                    }
                }
                .assistantActionButton(accent: source.kind == .consumable ? BG3Theme.warning : BG3Theme.gold)
                .controlSize(.small)
                .disabled(future)
            }
        }
    }

    private func sourceEffect(_ source: AbilityPlanSource) -> String {
        source.mode == .add ? "+\(source.value)" : "-> \(source.value)"
    }

    private func sourceTiming(_ source: AbilityPlanSource) -> String {
        if source.minimumLevel > 1 { return "from L\(source.minimumLevel)" }
        return switch source.kind {
        case .equipment: "while equipped"
        case .consumable: "while active"
        case .permanent: "once recorded"
        case .asi, .feat: "level choice"
        }
    }

    private func sourceColor(_ kind: AbilityPlanSourceKind) -> Color {
        switch kind {
        case .asi, .feat: Color(red: 0.46, green: 0.72, blue: 0.95)
        case .permanent: BG3Theme.success
        case .equipment: BG3Theme.gold
        case .consumable: BG3Theme.warning
        }
    }

    private func signed(_ value: Int) -> String { value >= 0 ? "+\(value)" : "\(value)" }

}

struct PartyAbilityTable: View {
    let setup: AbilitySetupPlan

    var body: some View {
        VStack(spacing: 0) {
            abilityRow(label: "", values: Ability.allCases.map(\.shortName), heading: true)
            Divider().opacity(0.6)
            abilityRow(label: "1  Point buy", values: Ability.allCases.map { String($0.value(in: setup.pointBuyScores)) })
            abilityRow(label: "2  Bonus", values: Ability.allCases.map { ability in
                ability == setup.bonusTwo ? "+2" : ability == setup.bonusOne ? "+1" : "-"
            })
            Divider().opacity(0.6)
            abilityRow(label: "3  Enter", values: Ability.allCases.map { String($0.value(in: setup.finalScores)) }, emphasized: true)
        }
        .background(BG3Theme.ink.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BG3Theme.bronze.opacity(0.36), lineWidth: 0.7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("BG3 Ability Points recipe")
    }

    private func abilityRow(label: String, values: [String], heading: Bool = false, emphasized: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(heading ? BG3Type.caption : BG3Type.captionBold)
                .foregroundStyle(emphasized ? BG3Theme.gold : BG3Theme.mutedParchment)
                .frame(width: 72, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(heading ? BG3Type.captionBold : emphasized ? BG3Type.rowTitle : BG3Type.captionBold)
                    .foregroundStyle(emphasized ? BG3Theme.parchment : heading ? BG3Theme.gold : BG3Theme.parchment)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, heading ? 5 : 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(abilityRowAccessibilityLabel(label: label, values: values))
    }

    private func abilityRowAccessibilityLabel(label: String, values: [String]) -> String {
        let cells = zip(Ability.allCases, values)
            .map { pair in "\(pair.0.displayName) \(pair.1)" }
            .joined(separator: ", ")
        return label.isEmpty ? "Ability columns: \(cells)" : "\(label): \(cells)"
    }
}
