import Foundation

/// The one derivation of "what is the player doing right now", in precedence
/// order: player-chosen gear target, then — in guided acts — the walkthrough
/// step or fight checkpoint. Every surface (Now page, peek card, overlay
/// title) switches over this instead of re-deriving the precedence.
enum CurrentGoal {
    case target(GearTargetContext)
    case step(WalkthroughStep)
    case checkpoint(RouteCheckpoint)
    case laterAct
    case routeComplete
}

extension AppState {
    var currentGoal: CurrentGoal {
        if let context = gearTargetContext { return .target(context) }
        guard activeRouteAvailable else { return .laterAct }
        if let step = currentWalkthroughStep { return .step(step) }
        if let checkpoint = currentCheckpoint { return .checkpoint(checkpoint) }
        return .routeComplete
    }

    /// Any actionable goal: target, step, or checkpoint.
    var hasCurrentTask: Bool {
        switch currentGoal {
        case .target, .step, .checkpoint: true
        case .laterAct, .routeComplete: false
        }
    }

    /// A guide-driven goal (step or checkpoint) — level gates and danger
    /// ratings only exist for these.
    var hasGuidedGoal: Bool {
        switch currentGoal {
        case .step, .checkpoint: true
        case .target, .laterAct, .routeComplete: false
        }
    }

    var currentActivityTitle: String {
        switch currentGoal {
        case .target(let context): "Get \(context.gear.item)"
        case .step(let step): step.title
        case .checkpoint(let checkpoint): checkpoint.name
        case .laterAct: currentActGuide?.title ?? "Act \(selectedAct)"
        case .routeComplete: routeHasConsequentialSkips ? "Act \(selectedAct) resolved with skips" : "Act \(selectedAct) complete"
        }
    }

    var currentActivityArea: String {
        switch currentGoal {
        case .target(let context): context.gear.region
        case .step(let step): step.area
        case .checkpoint(let checkpoint): checkpoint.area
        case .laterAct, .routeComplete: ""
        }
    }

    var currentActivityMinimumLevel: Int {
        switch currentGoal {
        case .target(let context): context.gear.minimumLevel ?? lowestPartyLevel
        case .step(let step): step.minimumLevel
        case .checkpoint(let checkpoint): checkpoint.minimumLevel
        case .laterAct, .routeComplete: lowestPartyLevel
        }
    }

    var currentActivityAvoid: String {
        switch currentGoal {
        case .step(let step): step.incident?.never ?? step.avoid
        case .checkpoint(let checkpoint): checkpoint.failureConditions.first ?? checkpoint.advice
        case .target: "Confirm the acquisition before marking this target complete."
        case .laterAct: activeGuideLoaded ? "Step-by-step route guidance is not available for this act yet." : statusMessage
        case .routeComplete: routeHasConsequentialSkips
            ? "Revisit required or recommended skipped steps before treating this route as complete."
            : (selectedAct < 3 ? "Review the Act \(selectedAct + 1) gate before advancing." : "The final route is resolved.")
        }
    }

    var currentActivityDanger: String {
        switch currentGoal {
        case .step(let step):
            if let checkpointId = step.checkpointId,
               let danger = route.first(where: { $0.id == checkpointId })?.danger { return danger }
            if step.incident != nil { return "high" }
            return step.kind == "dialogue" ? "medium" : (currentCheckpoint?.danger ?? "low")
        case .checkpoint(let checkpoint): return checkpoint.danger
        case .target, .laterAct, .routeComplete: return "low"
        }
    }
}
