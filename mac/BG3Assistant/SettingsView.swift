import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show overlay while BG3 is running", isOn: $appState.showOverlay)
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { enabled in
                            if let error = LoginItem.setEnabled(enabled) { appState.errorMessage = error }
                        }
                    )
                )
                Picker("Collapsed overlay", selection: $appState.overlayDensity) {
                    ForEach(OverlayDensity.allCases) { density in Text(density.rawValue).tag(density) }
                }
            }

            Section("AI Chat") {
                SecureField("OpenRouter API key", text: $appState.openRouterKeyDraft)
                Text("Optional. Enables AI answers and a removable one-shot BG3 screenshot when chat opens.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { Task { await appState.saveOpenRouterKey() } } label: {
                        Label("Save Key", systemImage: "key.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.openRouterKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if appState.hasOpenRouterKey {
                        Button(role: .destructive) { Task { await appState.removeOpenRouterKey() } } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    Spacer()
                    Text(appState.hasOpenRouterKey ? "Ready" : "Guide-only without a key")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Honor Runs") {
                Picker("Active run", selection: Binding(
                    get: { appState.run.id },
                    set: { appState.switchRun(to: $0) }
                )) {
                    ForEach(appState.savedRuns) { saved in
                        Text("\(saved.name) · L\(saved.partyLevel)").tag(saved.id)
                    }
                }
                HStack {
                    TextField("Current run name", text: $appState.runNameDraft)
                    Button("Rename", action: appState.renameCurrentRun)
                        .buttonStyle(.bordered)
                        .disabled(appState.runNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                TextField("New run name (optional)", text: $appState.newRunNameDraft)
                Button {
                    appState.newRunConfirmation = true
                } label: {
                    Label("New Honor Run", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup("Diagnostics") {
                LabeledContent("Baldur's Gate 3", value: appState.gameDetected ? "Running" : "Not running")
                LabeledContent("Local service", value: appState.backendHealthy ? "Ready" : "Unavailable")
                if let error = appState.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(BG3Theme.control)
        .padding(.vertical, 8)
        .confirmationDialog(
            "Create a new Honor run? \(appState.currentRunName) stays saved and can be resumed anytime.",
            isPresented: $appState.newRunConfirmation
        ) {
            Button("Create Run", action: appState.startNewRun)
            Button("Cancel", role: .cancel) {}
        }
    }
}
