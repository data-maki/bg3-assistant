import Foundation

/// Run lifecycle and cross-process persistence. The map webapp writes the
/// same store through the backend, so every save first polls for a
/// concurrent change and adopts it instead of clobbering it.
extension AppState {
    /// Adopt a run that arrived from the shared store (conflict reload or
    /// background poll), resetting the per-run transients that must not
    /// outlive the snapshot they were captured against.
    func adoptRun(_ shared: HonorRun, token: RunStore.ChangeToken?) {
        let guideContextChanged = run.id != shared.id || selectedAct != (shared.selectedAct)
        run = shared
        runNameDraft = shared.name ?? "Honor Run"
        partyUndoState = nil
        sharedRunToken = token
        reloadSavedRuns()
        if guideContextChanged {
            chatLines = []
            chatScreenshot = nil
            resetGuideContext()
        } else {
            refreshReadiness()
        }
    }

    func persistRun() {
        switch runStore.pollActiveRun(since: sharedRunToken) {
        case .changed(let shared, let token) where shared.id == run.id:
            adoptRun(shared, token: token)
            errorMessage = "The map changed this run first. Its latest Party state was reloaded; retry your action."
            return
        case .tokenRefreshed(let token):
            sharedRunToken = token
        case .unchanged, .changed:
            break
        }
        do {
            try runStore.save(run)
            sharedRunToken = runStore.changeToken(for: run)
            reloadSavedRuns()
        } catch {
            errorMessage = "Could not save run: \(error.localizedDescription)"
        }
    }

    /// Background poll (every status refresh): pick up map-side edits.
    func reloadSharedRunIfNeeded() {
        switch runStore.pollActiveRun(since: sharedRunToken) {
        case .changed(let shared, let token) where shared.id == run.id:
            adoptRun(shared, token: token)
        case .tokenRefreshed(let token):
            sharedRunToken = token
        case .unchanged, .changed:
            break
        }
    }

    func startNewRun() {
        createNewRun(usingCurrentPartyPreset: false)
    }

    func startNewRunWithCurrentPartyPreset() {
        createNewRun(usingCurrentPartyPreset: true)
    }

    func startUpdatedRun(guideVersion: String, availableBuilds: [BuildSummary]) {
        createNewRun(
            usingCurrentPartyPreset: true,
            guideVersion: guideVersion,
            availableBuilds: availableBuilds,
            requestedName: ""
        )
    }

    private func createNewRun(
        usingCurrentPartyPreset: Bool,
        guideVersion: String? = nil,
        availableBuilds: [BuildSummary]? = nil,
        requestedName: String? = nil
    ) {
        let nameDraft = requestedName ?? newRunNameDraft
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Honor Run \(savedRuns.count + 1)" : trimmedName
        let targetGuideVersion = guideVersion ?? self.availableGuideVersion
        let targetBuilds = availableBuilds ?? builds
        var fresh = HonorRun()
        if usingCurrentPartyPreset {
            fresh = run.freshRun(
                name: name,
                guideVersion: targetGuideVersion,
                availableBuilds: targetBuilds
            )
        } else {
            fresh.name = name
            fresh.createdAt = .now
            fresh.normalizeRoster()
            fresh.guideVersion = targetGuideVersion
        }
        run = fresh
        resetGuideContext()
        partyUndoState = nil
        runNameDraft = fresh.name ?? "Honor Run"
        newRunNameDraft = ""
        skipNoteDraft = ""
        combatCardPinned = false
        chatLines = []
        chatScreenshot = nil
        persistRun()
        reloadSavedRuns()
    }

    func renameCurrentRun() {
        let name = runNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run.name = name
        persistRun()
        reloadSavedRuns()
    }

    func switchRun(to runID: String) {
        guard runID != run.id else { return }
        persistRun()
        do {
            var selected = try runStore.activate(runID: runID)
            selected.normalizeRoster()
            adoptRun(selected, token: runStore.changeToken(for: selected))
            skipNoteDraft = ""
            combatCardPinned = false
            chatLines = []
            chatScreenshot = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadSavedRuns() {
        savedRuns = runStore.listRuns().map { saved in
            SavedRunSummary(
                id: saved.id,
                name: saved.name ?? "Honor Run",
                completedSteps: saved.walkthroughProgress.values.filter(\.countsAsCompleted).count,
                partyLevel: saved.activeParty.map(\.level).min() ?? 1
            )
        }
    }

    func persistSettings() {
        let settings = AssistantSettings(
            overlayDensity: overlayDensity.rawValue,
            onboardingSeenVersion: onboardingSeenVersion,
            seenHints: seenHints.isEmpty ? nil : seenHints.sorted()
        )
        do { try runStore.saveSettings(settings) }
        catch { errorMessage = "Could not save settings: \(error.localizedDescription)" }
    }
}
