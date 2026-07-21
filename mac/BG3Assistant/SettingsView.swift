import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var openRouterKey = ""

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $appState.aiProvider) {
                    Text("Choose a provider").tag(AIProvider?.none)
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(Optional(provider))
                    }
                }
                if appState.aiProvider == .localQwen {
                    LabeledContent("Model", value: OllamaRuntime.model)
                    if appState.localAIInstalled {
                        Label("Installed and ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if appState.isInstallingLocalAI {
                        ProgressView(value: appState.localAIInstallProgress)
                        Text("Downloading approximately 2.5 GB. Keep the assistant open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Download Qwen3 4B", action: appState.installLocalAI)
                            .buttonStyle(.borderedProminent)
                    }
                } else if appState.aiProvider == .openRouter {
                    LabeledContent("Model", value: AssistantAIClient.openRouterModel)
                    if appState.hasOpenRouterKey {
                        HStack {
                            Label("API key saved in Keychain", systemImage: "key.fill")
                            Spacer()
                            Button("Remove", role: .destructive, action: appState.deleteOpenRouterKey)
                        }
                    } else {
                        HStack {
                            SecureField("OpenRouter API key", text: $openRouterKey)
                            Button("Save") {
                                if appState.saveOpenRouterKey(openRouterKey) {
                                    openRouterKey = ""
                                }
                            }
                            .disabled(openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                Text("OpenRouter keys are stored only in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Label("Replay Tour", systemImage: "sparkles")
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

            DisclosureGroup("Legal & Credits") {
                Text("BG3 Honor Mode Assistant is unofficial Fan Content permitted under the Fan Content Policy. Not approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. ©Wizards of the Coast LLC.")
                    .font(.caption)
                Text("This app is not commissioned, sponsored, endorsed, or approved by Larian Studios.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    "Baldur's Gate 3 Fan Content Terms",
                    destination: URL(string: "https://baldursgate3.game/bg3-fan-content-terms/")!
                )
                Link(
                    "Wizards Fan Content Policy",
                    destination: URL(string: "https://company.wizards.com/en/legal/fancontentpolicy")!
                )
                Link(
                    "Bg3.wiki Copyrights",
                    destination: URL(string: "https://bg3.wiki/wiki/bg3wiki:Copyrights")!
                )
                if let notices = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                    Button("Open Third-Party Notices") {
                        if !NSWorkspace.shared.open(notices) {
                            appState.errorMessage = "Could not open the bundled third-party notices."
                        }
                    }
                }
            }

            DisclosureGroup("Diagnostics") {
                LabeledContent("Baldur's Gate 3", value: appState.gameDetected ? "Running" : "Not running")
                LabeledContent("Bundled guide", value: appState.activeGuideLoaded ? "Ready" : "Unavailable")
                LabeledContent("AI provider", value: appState.aiProvider?.title ?? "Not configured")
                LabeledContent("AI features", value: appState.buildImportAvailable ? "Available" : "Setup required")
                if let error = appState.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(BG3Theme.control)
        .padding(.vertical, 8)
        .task { await appState.refreshAIProviderStatus() }
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
