import Foundation

extension AppState {
    func chooseAIProvider(_ provider: AIProvider) {
        aiProvider = provider
        Task { await refreshAIProviderStatus() }
    }

    func refreshAIProviderStatus() async {
        hasOpenRouterKey = (try? CredentialStore.openRouterKey())?.isEmpty == false
        if aiProvider == .localQwen {
            localAIInstalled = (try? await ollamaRuntime.isModelInstalled()) == true
        }
    }

    @discardableResult
    func saveOpenRouterKey(_ key: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CredentialStore.saveOpenRouterKey(value)
            guard try CredentialStore.openRouterKey() == value else {
                throw CredentialStoreError.verificationFailed
            }
            hasOpenRouterKey = !value.isEmpty
            errorMessage = nil
            return true
        } catch {
            hasOpenRouterKey = false
            errorMessage = "Could not save the API key: \(error.localizedDescription)"
            return false
        }
    }

    func deleteOpenRouterKey() {
        do {
            try CredentialStore.deleteOpenRouterKey()
            hasOpenRouterKey = false
        } catch {
            errorMessage = "Could not remove the API key: \(error.localizedDescription)"
        }
    }

    func installLocalAI() {
        guard !isInstallingLocalAI else { return }
        isInstallingLocalAI = true
        localAIInstallProgress = nil
        Task {
            do {
                try await ollamaRuntime.installModel { progress in
                    Task { @MainActor in self.localAIInstallProgress = progress }
                }
                localAIInstalled = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isInstallingLocalAI = false
        }
    }
}
