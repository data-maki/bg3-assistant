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

}
