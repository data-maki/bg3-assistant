import SwiftUI

struct BuildImportView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var assignToMemberID: String? = nil
    @State private var pendingAssignment: BuildSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORT REUSABLE BUILD")
                .font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
            Text(assignToMemberID == nil
                ? "Paste one public build guide. It will be added to every character's build picker."
                : "Paste one public build guide. After review, it will be assigned to this character and remain available to everyone.")
                .font(.caption).foregroundStyle(BG3Theme.mutedParchment)
            if !appState.buildImportAvailable {
                Label(
                    "Choose and configure a local model or OpenRouter in Settings.",
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(9)
                    .bg3InsetSurface(accent: BG3Theme.warning)
            } else if let provider = appState.aiProvider {
                Label("Importing with \(provider.title)", systemImage: provider.isLocal ? "desktopcomputer" : "cloud")
                    .font(.caption2)
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            HStack(spacing: 6) {
                TextField("https://…", text: $appState.loadoutURLDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(appState.isImportingLoadout)
                Button(action: beginImport) {
                    if appState.isImportingLoadout {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
                .disabled(importIsDisabled)
            }
            if let status = appState.loadoutImportStatus {
                Text(status).font(.caption2).foregroundStyle(BG3Theme.mutedParchment)
            }
            if let json = appState.loadoutImportJSON {
                DisclosureGroup("Imported build JSON") {
                    ScrollView {
                        Text(json)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.caption2.bold())
            }
        }
        .padding(14)
        .frame(width: 390)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .background(BG3Theme.ink)
        .confirmationDialog(
            "Replace the current build?",
            isPresented: Binding(
                get: { pendingAssignment != nil },
                set: { if !$0 { pendingAssignment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Assign imported build", role: .destructive) {
                guard let build = pendingAssignment,
                      let memberID = assignToMemberID,
                      let member = appState.roster.first(where: { $0.id == memberID }) else { return }
                assign(build, to: member)
            }
            Button("Keep current build", role: .cancel) { pendingAssignment = nil }
        } message: {
            Text("Permanent rewards stay with the character. Temporary effects and build-specific setup confirmation will be cleared.")
        }
    }

    private var importIsDisabled: Bool {
        appState.isImportingLoadout
            || !appState.buildImportAvailable
            || appState.loadoutURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginImport() {
        Task {
            guard let build = await appState.importBuild() else { return }
            if let assignToMemberID,
               let member = appState.roster.first(where: { $0.id == assignToMemberID }) {
                if appState.buildReplacementNeedsConfirmation(for: member) {
                    pendingAssignment = build
                } else {
                    assign(build, to: member)
                }
            }
        }
    }

    private func assign(_ build: BuildSummary, to member: PartyMember) {
        appState.assignBuild(build.id, to: member)
        pendingAssignment = nil
        dismiss()
    }
}
