import Foundation

struct RouteDependencyPresentation {
    let note: String?
    let requiresAttention: Bool
}

extension AppState {
    /// Why a step can't (or shouldn't) be done yet, phrased for the row's
    /// second line: nil note = ready, note without attention = sequenced
    /// later, attention = the player changed something a prerequisite assumed.
    func routeDependencyPresentation(for step: WalkthroughStep) -> RouteDependencyPresentation {
        let blockers = walkthroughBlockers(step)
        guard !blockers.isEmpty else {
            let currentPhaseOrder = recommendedWalkthroughStep?.phaseOrder
                ?? activeWalkthroughSteps.map(\.phaseOrder).min()
            if let currentPhaseOrder, step.phaseOrder > currentPhaseOrder {
                return RouteDependencyPresentation(note: step.phase, requiresAttention: false)
            }
            return RouteDependencyPresentation(note: nil, requiresAttention: false)
        }

        for dependency in step.dependencies where dependency.kind != "warning_only" {
            guard let prerequisite = walkthrough.first(where: { $0.id == dependency.stepId }) else { continue }
            let disposition = walkthroughDisposition(prerequisite)
            let satisfied: Bool
            switch dependency.kind {
            case "completion_required":
                satisfied = disposition.countsAsCompleted
            case "outcome_required":
                // Caught-up steps carry no recorded outcome; assume the
                // guide's recommended path (mirrors RunSafety).
                satisfied = disposition == .caughtUp
                    || (disposition == .completed
                        && walkthroughOutcome(prerequisite) == dependency.requiredOutcome)
            default:
                satisfied = disposition != .pending
            }
            guard !satisfied else { continue }

            if disposition == .pending {
                return RouteDependencyPresentation(note: "After \(prerequisite.title)", requiresAttention: false)
            }
            if disposition == .skipped {
                return RouteDependencyPresentation(note: "Revisit \(prerequisite.title)", requiresAttention: true)
            }
            return RouteDependencyPresentation(note: "Route changed after \(prerequisite.title)", requiresAttention: true)
        }
        return RouteDependencyPresentation(note: blockers[0], requiresAttention: true)
    }
}
