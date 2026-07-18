import Foundation

/// Overlay presentation: what the floating panel shows and when it appears.
extension AppState {
    func togglePlanner() {
        overlayExpanded.toggle()
    }

    func showOverlayGoal() {
        overlayExpanded = false
        overlayDensity = .focus
        forceOverlay = true
        showOverlay = true
    }

    func collapseOverlayToPet() {
        overlayExpanded = false
        overlayDensity = .minimal
    }

    func showOverlayNow() {
        forceOverlay = true
        showOverlay = true
        syncOverlay()
    }

    func showPlannerNow() {
        plannerTab = .current
        forceOverlay = true
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func showPlannerRoute() {
        plannerTab = .route
        forceOverlay = true
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func openSettings() {
        plannerTab = .settings
        forceOverlay = true
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func openDialogue() {
        // Dialogue lives inside the route now: jump to the route with the
        // current conversation step focused and expanded.
        plannerTab = .route
        focusedWalkthroughStepId = currentDialogueStep?.id ?? currentWalkthroughStep?.id
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
    }

    func hideAssistantOverlay() {
        forceOverlay = false
        showOverlay = false
    }

    func pinCurrentFight() {
        guard currentCheckpoint != nil, readiness?.status != "blocked" else { return }
        combatCardPinned = true
        overlayExpanded = false
    }

    func unpinFight() { combatCardPinned = false }

    func syncOverlay() {
        // Never auto-present an empty guide shell over the game. Manual opens
        // remain available so startup errors can still be inspected.
        let guideReady = activeGuideLoaded
        if showOverlay && (forceOverlay || gameDetected && guideReady) { overlayController.show(appState: self, gameFrame: gameWindowFrame) }
        else { overlayController.hide() }
    }

    // MARK: - One-time hints

    /// Show a coach mark only when it can land: never over the wizard or a
    /// pinned fight, never twice, and at most one per session so a first play
    /// session is not a hint parade.
    func maybeShowHint(_ hint: HintID) {
        guard onboardingStep == nil,
              activeHint == nil,
              !hintShownThisSession,
              !combatCardPinned,
              !seenHints.contains(hint.rawValue) else { return }
        activeHint = hint
        hintShownThisSession = true
    }

    func dismissActiveHint() {
        guard let hint = activeHint else { return }
        seenHints.insert(hint.rawValue)
        persistSettings()
        activeHint = nil
    }
}
