import SwiftUI

/// One-character-at-a-time party setup and equipment surface.
struct PartyTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LoadoutTabView()
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

}

struct RosterMemberEditor: View {
    let member: PartyMember
    let builds: [BuildSummary]
    let onChange: (PartyMember) -> Void
    let onStatusChange: (RosterStatus) -> Void

    private var isCustom: Bool { member.isCustom == true }
    private var selectedBuild: BuildSummary? { builds.first(where: { $0.id == member.buildId }) }
    private var currentBuildLevel: BuildLevel? { selectedBuild?.levels.last(where: { $0.level <= member.level }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if isCustom {
                    TextField("Character name", text: Binding(get: { member.name }, set: { var copy = member; copy.name = $0; onChange(copy) }))
                        .textFieldStyle(.roundedBorder).frame(width: 116)
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
