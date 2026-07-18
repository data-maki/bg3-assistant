import Foundation

/// Intake-wizard flow. The wizard is a third overlay mode (above planner and
/// peek in `OverlayView`); it stays active until finished or skipped, and
/// quitting mid-wizard re-shows it on the next launch.
extension AppState {
    func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        if let next = step.next(for: onboardingMode) { onboardingStep = next }
        else { finishOnboarding(completed: true) }
    }

    func regressOnboarding() {
        guard let step = onboardingStep,
              let previous = step.previous(for: onboardingMode) else { return }
        onboardingStep = previous
    }

    /// Welcome fork: a fresh run keeps the default Act 1 start.
    func chooseFreshRun() {
        onboardingMode = .fresh
        onboardingCatchUpCheckpointId = nil
        advanceOnboarding()
    }

    func chooseMidRun() {
        onboardingMode = .midRun
        advanceOnboarding()
    }

    /// Catch-up act switch: load that act's guide so the landmark list is
    /// real route data, not a placeholder.
    func selectOnboardingAct(_ act: Int) {
        guard act != selectedAct, (1...3).contains(act) else { return }
        run.selectedAct = act
        onboardingCatchUpCheckpointId = nil
        persistRun()
        resetGuideContext()
        Task { await loadRouteIfNeeded() }
    }

    /// Apply the selected landmark (nil = start of the act: nothing to mark)
    /// and move on. The ledger write preserves any explicit history.
    func applyCatchUpAndAdvance() {
        defer { advanceOnboarding() }
        guard let checkpointId = onboardingCatchUpCheckpointId,
              let ledger = CatchUp.ledger(
                  markingThrough: checkpointId,
                  walkthrough: walkthrough,
                  existing: run.walkthroughProgress ?? [:]
              ) else { return }
        run.walkthroughProgress = ledger
        run.focusedWalkthroughStepId = nil
        run.selectedCheckpointId = nil
        syncRegionToRecommendation()
        persistRun()
        refreshReadiness()
    }

    /// Finishing and skipping share one path so the wizard never re-nags.
    /// Only a real finish counts as completed — that consent gates the
    /// login item, which earlier builds enabled silently on first launch.
    func finishOnboarding(completed: Bool) {
        onboardingSeenVersion = OnboardingStep.version
        if completed, onboardingEnableLoginItem, !LoginItem.isEnabled {
            if let error = LoginItem.setEnabled(true) { errorMessage = error }
        }
        persistSettings()
        onboardingStep = nil
        // Land on the peek card showing this run's real next task.
        overlayExpanded = false
        forceOverlay = true
        showOverlay = true
    }

    func skipOnboarding() { finishOnboarding(completed: false) }

    func replayOnboarding() {
        onboardingMode = .fresh
        onboardingCatchUpCheckpointId = nil
        seenHints = []
        persistSettings()
        onboardingStep = .welcome
        forceOverlay = true
        showOverlay = true
    }
}
