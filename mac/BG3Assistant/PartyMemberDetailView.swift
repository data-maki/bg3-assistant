import SwiftUI

struct PartyMemberDetailView: View {
    private static let importBuildSelection = "__import-build__"

    @EnvironmentObject private var appState: AppState
    let memberID: String
    let onBack: () -> Void
    let onAbilities: () -> Void
    let onManualBuild: () -> Void
    let onReset: () -> Void

    @State private var pendingBuildID: String?
    @State private var showsBuildBrowser = false
    @State private var showsBuildImport = false
    @State private var showsDismissConfirmation = false

    private var member: PartyMember? { appState.roster.first { $0.id == memberID } }
    private var build: BuildSummary? {
        guard let id = member?.buildId else { return nil }
        return appState.builds.first { $0.id == id }
    }

    var body: some View {
        if let member {
            detail(member)
                .confirmationDialog(
                    "Replace \(member.name)'s build?",
                    isPresented: Binding(
                        get: { pendingBuildID != nil },
                        set: { if !$0 { pendingBuildID = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Replace build", role: .destructive) {
                        appState.assignBuild(pendingBuildID?.isEmpty == true ? nil : pendingBuildID, to: member)
                        pendingBuildID = nil
                    }
                    Button("Cancel", role: .cancel) { pendingBuildID = nil }
                } message: {
                    Text("Permanent rewards stay with the character. Temporary effects and build-specific setup confirmation will be cleared.")
                }
                .confirmationDialog(
                    "Dismiss \(member.name)?",
                    isPresented: $showsDismissConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Dismiss hireling", role: .destructive) {
                        if appState.removeHireling(member) { onBack() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The hireling and their equipment assignments will be removed from this run.")
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

    private func detail(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                backButton
                Spacer()
                StatusChip(text: member.rosterStatus.label, tint: member.rosterStatus.tint)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    identity(member)
                    abilityDistribution(member)
                    guidance(member)
                    manualBuildCard(member)
                    buildSelection(member)
                    destructiveControls(member)
                }
                .padding(.trailing, 6)
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Party", systemImage: "chevron.left").font(BG3Type.captionBold)
        }
        .assistantActionButton()
        .controlSize(.small)
    }

    private func identity(_ member: PartyMember) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if member.isCustom == true {
                    TextField("Character name", text: Binding(
                        get: { member.name },
                        set: { value in
                            var copy = member
                            copy.name = value
                            appState.updatePartyMember(copy)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(BG3Type.rowTitle)
                    .accessibilityLabel("Character name")
                } else {
                    Text(member.name)
                        .font(BG3Type.pageTitle)
                        .foregroundStyle(BG3Theme.parchment)
                        .lineLimit(1)
                }
                Text(identityDetail(member))
                    .font(BG3Type.caption)
                    .foregroundStyle(member.isHireling == true ? BG3Theme.gold : BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("LEVEL")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.mutedParchment)
                Picker("Level", selection: Binding(
                    get: { member.level },
                    set: { appState.updatePartyLevel($0, for: member) }
                )) {
                    ForEach(1...12, id: \.self) { Text("Level \($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 96)
                .controlSize(.small)
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: member.rosterStatus.tint)
    }

    private func identityDetail(_ member: PartyMember) -> String {
        if member.isHireling == true,
           let hireling = WithersHireling.matching(member.name) {
            return "\(hireling.race) · Withers hireling"
        }
        return member.manualBuild?.name ?? build?.name ?? member.className ?? "No build"
    }

    private func manualBuildCard(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("BUILD IT YOURSELF")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                if member.manualBuild != nil {
                    StatusChip(text: "ACTIVE", tint: BG3Theme.success, filled: true)
                }
            }
            Text("Set base ability points, choose a class at every character level, and pick subclasses, feats, spells, and class options through Level 12.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onManualBuild()
            } label: {
                Label(
                    member.manualBuild == nil ? "Create manual build" : "Edit \(member.manualBuild?.name ?? "manual build")",
                    systemImage: "hammer.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .assistantActionButton(accent: BG3Theme.gold, prominent: member.manualBuild == nil)
        }
        .padding(10)
        .bg3InsetSurface(accent: member.manualBuild == nil ? BG3Theme.bronze : BG3Theme.success)
    }

    @ViewBuilder private func guidance(_ member: PartyMember) -> some View {
        if let build, let step = build.levels.last(where: { $0.level <= member.level }) {
            let exact = step.level == member.level
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    StatusChip(text: exact ? "NOW L\(step.level)" : "LATEST PLAN L\(step.level)", tint: exact ? BG3Theme.success : BG3Theme.control, filled: exact)
                    Spacer()
                    Text(build.name).font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold).lineLimit(1)
                }
                Text(step.take)
                    .font(BG3Type.rowTitle).foregroundStyle(BG3Theme.parchment)
                if !step.subclassChoice.isEmpty, step.subclassChoice != "-" {
                    FactRow(glyph: "◆", tint: BG3Theme.gold, text: step.subclassChoice)
                }
                if !step.choices.isEmpty, step.choices != "-" {
                    FactRow(glyph: "→", tint: BG3Theme.gold, text: step.choices)
                }
                if !step.tactics.isEmpty, step.tactics != "-" {
                    FactRow(glyph: "★", tint: BG3Theme.success, text: step.tactics)
                }
                if let next = build.levels.first(where: { $0.level > member.level }) {
                    Divider().opacity(0.5)
                    Text("Next L\(next.level): \(next.take)")
                        .font(BG3Type.captionBold).foregroundStyle(BG3Theme.mutedParchment)
                }
            }
            .padding(10)
            .bg3InsetSurface(accent: exact ? BG3Theme.success : BG3Theme.control)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(member.manualBuild == nil ? "No build assigned" : "Manual build active", systemImage: member.manualBuild == nil ? "exclamationmark.triangle.fill" : "hammer.fill")
                    .font(BG3Type.rowTitle).foregroundStyle(member.manualBuild == nil ? BG3Theme.warning : BG3Theme.success)
                Text(member.manualBuild == nil
                    ? "Choose, import, or create a build below."
                    : "Open the manual builder to record this level's class, feat, spell, and ability choices.")
                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            }
            .padding(10)
            .bg3InsetSurface(accent: BG3Theme.warning)
        }
    }

    private func abilityDistribution(_ member: PartyMember) -> AnyView {
        if let manual = member.manualBuild {
            let spent = AbilityProgression.pointBuyCost(manual.abilityScores)
            return AnyView(
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("ABILITY SCORES")
                            .font(BG3Type.overline)
                            .foregroundStyle(BG3Theme.gold)
                        Spacer()
                        StatusChip(
                            text: spent == 27 ? "27/27 VALID" : "\(max(spent, 0))/27",
                            tint: spent == 27 ? BG3Theme.success : BG3Theme.warning,
                            filled: spent == 27
                        )
                    }
                    HStack(spacing: 5) {
                        ForEach(Ability.allCases) { ability in
                            VStack(spacing: 2) {
                                Text(ability.shortName)
                                    .font(BG3Type.captionBold)
                                    .foregroundStyle(BG3Theme.gold)
                                Text("\(ability.value(in: manual.abilityScores))")
                                    .font(BG3Type.rowTitle)
                                    .foregroundStyle(BG3Theme.parchment)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Button("Edit ability points and levels", action: onManualBuild)
                        .assistantActionButton(accent: BG3Theme.gold, prominent: true)
                }
                .padding(10)
                .bg3InsetSurface(accent: spent == 27 ? BG3Theme.success : BG3Theme.gold)
            )
        }
        let setup = AbilityProgression.activeSetup(in: build, at: member.level)
        let applied = setup.map { member.appliedAbilitySetupId == $0.id } ?? false
        return AnyView(VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("ABILITY SCORES")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                Button(action: onAbilities) {
                    HStack(spacing: 3) {
                        Text("Boosts & progression")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.plain)
                .font(BG3Type.captionBold)
                .foregroundStyle(BG3Theme.gold)
            }
            if let setup {
                HStack(spacing: 6) {
                    Text("\(setup.label) · Enter these values in BG3")
                        .font(BG3Type.captionBold)
                        .foregroundStyle(BG3Theme.parchment)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    StatusChip(
                        text: applied ? "RECORDED" : "ACTION NEEDED",
                        tint: applied ? BG3Theme.success : BG3Theme.warning,
                        filled: applied
                    )
                }
                PartyAbilityTable(setup: setup)
                HStack(spacing: 7) {
                    Text("27-point buy · Start as \(setup.firstClass)")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if !applied {
                        Button("Mark applied") {
                            appState.applyAbilitySetup(setup, to: member)
                        }
                        .assistantActionButton(accent: BG3Theme.success, prominent: true)
                        .controlSize(.small)
                        .disabled(!AbilityProgression.isValidBG3Setup(setup))
                    }
                }
            } else {
                Label("No validated BG3 point-buy recipe for this build", systemImage: "exclamationmark.triangle.fill")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.warning)
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: applied ? BG3Theme.success : BG3Theme.gold)
        )
    }

    private func buildSelection(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BUILD").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                Spacer()
                Button(showsBuildBrowser ? "Hide comparison" : "Compare builds") {
                    withAnimation { showsBuildBrowser.toggle() }
                }
                .buttonStyle(.plain).font(BG3Type.captionBold).foregroundStyle(BG3Theme.gold)
            }
            Picker("Reviewed build", selection: Binding(
                get: { member.buildId ?? "" },
                set: { value in
                    if value == Self.importBuildSelection {
                        showsBuildImport = true
                    } else {
                        requestBuild(value.isEmpty ? nil : value, for: member)
                    }
                }
            )) {
                Text("No reviewed build").tag("")
                ForEach(appState.builds) { Text($0.name).tag($0.id) }
                Divider()
                Label("Import build from URL...", systemImage: "link.badge.plus").tag(Self.importBuildSelection)
            }
            .controlSize(.small)
            .popover(isPresented: $showsBuildImport, arrowEdge: .top) {
                BuildImportView(assignToMemberID: member.id).environmentObject(appState)
            }

            if let build {
                HStack(spacing: 5) {
                    StatusChip(text: build.honorStatus.uppercased(), tint: BG3Theme.success)
                    Text(build.finalSplit).font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
                }
                FactRow(glyph: "◆", tint: BG3Theme.gold, text: build.role, secondary: true)
                if !build.caveat.isEmpty {
                    FactRow(glyph: "!", tint: BG3Theme.warning, text: build.caveat, secondary: true)
                }
            }

            if showsBuildBrowser {
                VStack(spacing: 6) {
                    ForEach(appState.builds) { candidate in
                        Button { requestBuild(candidate.id, for: member) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(candidate.name).font(BG3Type.captionBold).foregroundStyle(BG3Theme.parchment)
                                    Spacer()
                                    if candidate.id == member.buildId {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(BG3Theme.success)
                                    }
                                }
                                Text("\(candidate.role) · \(candidate.finalSplit)")
                                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).lineLimit(2)
                                Text(candidate.honorStatus)
                                    .font(BG3Type.captionBold).foregroundStyle(BG3Theme.success)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .bg3InsetSurface(accent: candidate.id == member.buildId ? BG3Theme.success : BG3Theme.bronze)
                    }
                }
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func destructiveControls(_ member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DANGEROUS ACTIONS").font(BG3Type.overline).foregroundStyle(BG3Theme.danger)
            Button("Reset character plan...", role: .destructive, action: onReset)
                .assistantActionButton(accent: BG3Theme.danger)
            if member.isHireling == true {
                Button("Dismiss hireling...", role: .destructive) { showsDismissConfirmation = true }
                    .assistantActionButton(accent: BG3Theme.danger)
                    .disabled(member.rosterStatus == .active)
                if member.rosterStatus == .active {
                    Text("Send this hireling to Camp before dismissal.")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                }
            }
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.danger)
    }

    private func requestBuild(_ buildID: String?, for member: PartyMember) {
        guard buildID != member.buildId else { return }
        if appState.buildReplacementNeedsConfirmation(for: member) {
            pendingBuildID = buildID ?? ""
        } else {
            appState.assignBuild(buildID, to: member)
        }
    }

}
