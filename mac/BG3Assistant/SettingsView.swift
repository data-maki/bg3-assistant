import AppKit
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
                Button {
                    appState.replayOnboarding()
                } label: {
                    Label("Replay Tour & Hints", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
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

            Section("Support") {
                Button {
                    var message = URLComponents()
                    message.scheme = "mailto"
                    message.path = "jcllobet@gmail.com"
                    message.queryItems = [
                        URLQueryItem(name: "subject", value: "BG3 Honor Mode Assistant bug report"),
                    ]
                    if let url = message.url, !NSWorkspace.shared.open(url) {
                        appState.errorMessage = "Could not open an email app. Report bugs to jcllobet@gmail.com."
                    }
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }
                Text("Opens your email app with the developer address filled in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Diagnostics") {
                LabeledContent("Baldur's Gate 3", value: appState.gameDetected ? "Running" : "Not running")
                LabeledContent("Backend service", value: appState.backendHealthy ? "Ready" : "Unavailable")
                LabeledContent("AI backend endpoint", value: appState.upstreamBackendEndpoint.baseURL.absoluteString)
                LabeledContent("AI features", value: appState.backendAIAvailable ? "Available" : "Unavailable")
                if !appState.upstreamBackendEndpoint.managesLocalBackend {
                    LabeledContent("TestFlight authentication", value: appState.backendAuthenticated ? "Verified" : "Unavailable")
                    if !appState.backendAuthenticated {
                        Button("Retry App Store Verification") {
                            appState.retryBackendAuthentication()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let quota = appState.buildImportQuota {
                    LabeledContent("Build-import attempts", value: "\(quota.remaining) of \(quota.limit) remaining")
                }
                if let message = appState.backendAuthenticationMessage {
                    Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
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
            Button("Use Current Characters & Builds", action: appState.startNewRunWithCurrentPartyPreset)
            Button("Start With Default Party", action: appState.startNewRun)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Both options reset levels, route progress, story outcomes, equipment, and act state. Presets keep the current roster and valid build selections.")
        }
    }
}
