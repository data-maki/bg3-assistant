import Foundation

/// Welcome-tour flow. The tour is a third overlay mode (above planner and
/// peek in `OverlayView`); it stays active until finished or skipped, and
/// quitting mid-tour re-shows it on the next launch.
extension AppState {
    func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        if let next = step.next { onboardingStep = next }
        else { finishOnboarding(opening: nil) }
    }

    func regressOnboarding() {
        guard let previous = onboardingStep?.previous else { return }
        onboardingStep = previous
    }

    func skipOnboarding() { finishOnboarding(opening: nil) }

    /// Finishing and skipping share one path so the tour never re-nags.
    func finishOnboarding(opening handoff: OnboardingHandoff?) {
        onboardingSeenVersion = OnboardingStep.version
        persistSettings()
        onboardingStep = nil
        switch handoff {
        case .party:
            plannerTab = .party
            overlayExpanded = true
        case .settings:
            plannerTab = .settings
            overlayExpanded = true
        case nil:
            // Land on the peek card so the surface just explained stays put.
            overlayExpanded = false
        }
        forceOverlay = true
        showOverlay = true
    }

    func replayOnboarding() {
        onboardingStep = .welcome
        forceOverlay = true
        showOverlay = true
    }
}
