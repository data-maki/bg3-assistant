import Foundation

// Pure run-safety derivation: next-step recommendation, dependency blockers,
// route phasing, and act-gate summaries. No AppState dependency — unit-testable.
enum RunSafety {
    static func walkthroughDisposition(
        _ step: WalkthroughStep,
        walkthroughProgress: [String: CheckpointDisposition]
    ) -> CheckpointDisposition {
        walkthroughProgress[step.id] ?? .pending
    }

    static func nextWalkthroughStep(
        walkthrough: [WalkthroughStep],
        walkthroughProgress: [String: CheckpointDisposition],
        selectedCheckpointId _: String?,
        walkthroughOutcomes: [String: String] = [:],
        partyLevel: Int
    ) -> WalkthroughStep? {
        let disposition: (WalkthroughStep) -> CheckpointDisposition = { step in
            walkthroughDisposition(step, walkthroughProgress: walkthroughProgress)
        }
        let pending = walkthrough.filter { disposition($0) == .pending }
        guard let phase = pending.map(\.phaseOrder).min() else { return nil }
        let phasePending = pending.filter { $0.phaseOrder == phase }.sorted { $0.order < $1.order }
        let eligible = phasePending.filter {
            dependencyBlockers(
                for: $0,
                walkthrough: walkthrough,
                walkthroughProgress: walkthroughProgress,
                walkthroughOutcomes: walkthroughOutcomes
            ).isEmpty
        }
        guard !eligible.isEmpty else { return nil }
        return eligible.first(where: { $0.minimumLevel <= partyLevel }) ?? eligible.first
    }

    static func dependencyBlockers(
        for step: WalkthroughStep,
        walkthrough: [WalkthroughStep],
        walkthroughProgress: [String: CheckpointDisposition],
        walkthroughOutcomes: [String: String] = [:]
    ) -> [String] {
        let titles = Dictionary(uniqueKeysWithValues: walkthrough.map { ($0.id, $0.title) })
        return step.dependencies.compactMap { dependency in
            let status = walkthroughProgress[dependency.stepId] ?? .pending
            let satisfied: Bool
            switch dependency.kind {
            case "warning_only":
                satisfied = true
            case "completion_required":
                satisfied = status.countsAsCompleted
            case "outcome_required":
                // caughtUp has no recorded outcome; catch-up assumes the
                // guide's recommended path, so the dependency must not nag.
                satisfied = status == .caughtUp
                    || (status == .completed
                        && walkthroughOutcomes[dependency.stepId] == dependency.requiredOutcome)
            default:
                satisfied = status != .pending
            }
            guard !satisfied else { return nil }
            if status == .skipped,
               dependency.kind == "completion_required" || dependency.kind == "outcome_required" {
                return "Revisit \(titles[dependency.stepId] ?? dependency.stepId) — \(dependency.reason)"
            }
            return dependency.reason
        }
    }

    /// Fight readiness for a checkpoint, computed locally from the loaded
    /// guide and run state. Ported from the backend's assess_readiness so the
    /// overlay never round-trips (or fails) over HTTP for a pure derivation;
    /// the backend keeps its own copy for chat grounding.
    static func assessReadiness(
        checkpoint: RouteCheckpoint,
        route: [RouteCheckpoint],
        walkthrough: [WalkthroughStep],
        activeParty: [PartyMember],
        completedIds: Set<String>,
        checkedPreparation: Set<String>,
        walkthroughProgress: [String: CheckpointDisposition],
        walkthroughOutcomes: [String: String],
        builds: [BuildSummary]
    ) -> ReadinessResponse {
        let partyLevel = activeParty.map(\.level).min() ?? 1
        var blockers: [String] = []
        var warnings: [String] = []
        var buildActions: [String] = []

        if activeParty.isEmpty {
            blockers.append("No active party is recorded; confirm the active group before using readiness.")
        } else if partyLevel < checkpoint.minimumLevel {
            blockers.append("Lowest party member is level \(partyLevel); guide minimum is level \(checkpoint.minimumLevel).")
        }
        let missingPrerequisites = checkpoint.prerequisites.filter { !completedIds.contains($0) }
        if !missingPrerequisites.isEmpty {
            let names = missingPrerequisites.map { id in route.first { $0.id == id }?.name ?? id }
            blockers.append("Unresolved reviewed route sequence: " + names.joined(separator: ", "))
        }
        if let owningStep = walkthrough.first(where: { $0.checkpointId == checkpoint.id }) {
            blockers.append(contentsOf: dependencyBlockers(
                for: owningStep,
                walkthrough: walkthrough,
                walkthroughProgress: walkthroughProgress,
                walkthroughOutcomes: walkthroughOutcomes
            ))
        }

        warnings.append(contentsOf: checkpoint.irreversibleWarnings)
        let uncheckedPreparation = checkpoint.preparation.filter { !checkedPreparation.contains($0) }
        if !uncheckedPreparation.isEmpty {
            warnings.append("Preparation not confirmed: " + uncheckedPreparation.joined(separator: "; "))
        }

        let buildsByID = Dictionary(builds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var assumedBuildSetup: [String] = []
        for member in activeParty {
            guard let buildID = member.buildId else { continue }
            guard let build = buildsByID[buildID] else {
                warnings.append("\(member.name) has an unknown build assignment (\(buildID)).")
                continue
            }
            let reviewedLevels = build.levels.filter { $0.level <= member.level }
            assumedBuildSetup.append(contentsOf: [build.role, build.playPattern, build.classProgression])
            assumedBuildSetup.append(contentsOf: reviewedLevels.map {
                "\($0.take) \($0.subclassChoice) \($0.choices) \($0.tactics)"
            })
            if let levelPlan = build.levels.first(where: { $0.level == member.level }) {
                buildActions.append("\(member.name) L\(member.level) (\(build.name)): \(levelPlan.take); \(levelPlan.tactics)")
            } else if let lastLevel = build.levels.last {
                warnings.append("\(member.name)'s reviewed \(build.name) plan ends at level \(lastLevel.level).")
            }
        }

        let capabilityTerms = [
            "silence", "calm emotions", "sanctuary", "command", "bludgeoning",
            "fire", "counterspell", "initiative", "control",
        ]
        let requestedText = ([checkpoint.advice] + checkpoint.preparation).joined(separator: " ").lowercased()
        let recordedCapabilities = (activeParty.flatMap(\.preparedTags) + assumedBuildSetup)
            .joined(separator: " ").lowercased()
        for capability in capabilityTerms
        where requestedText.contains(capability) && !recordedCapabilities.contains(capability) {
            warnings.append("Party capability not recorded: \(capability). Confirm the party has it or choose an alternative plan.")
        }

        let status = if !blockers.isEmpty { "blocked" }
        else if checkpoint.danger == "extreme" || !checkpoint.irreversibleWarnings.isEmpty { "danger" }
        else if checkpoint.danger == "high" || !warnings.isEmpty { "caution" }
        else { "ready" }
        var nextActions = Array(blockers.prefix(2)) + uncheckedPreparation.prefix(2) + buildActions.prefix(2)
        if nextActions.isEmpty { nextActions = [checkpoint.advice] }
        return ReadinessResponse(
            status: status,
            partyLevel: partyLevel,
            minimumLevel: checkpoint.minimumLevel,
            blockers: blockers,
            warnings: warnings,
            nextActions: nextActions
        )
    }

    static func nextCheckpoint(
        route: [RouteCheckpoint],
        dispositions: [String: CheckpointDisposition],
        selectedId: String?,
        partyLevel: Int
    ) -> RouteCheckpoint? {
        if let selectedId, let selected = route.first(where: { $0.id == selectedId }) { return selected }
        let pending = route.filter { (dispositions[$0.id] ?? .pending) == .pending }
        guard let phase = pending.map(routePhase).min() else { return nil }
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(dispositions.compactMap { $0.value != .pending ? $0.key : nil })
        let eligible = phasePending.filter { checkpoint in
            checkpoint.prerequisites.allSatisfy { resolved.contains($0) }
        }
        let candidates = eligible.isEmpty ? phasePending : eligible
        let atOrBelowLevel = candidates.filter { $0.minimumLevel <= partyLevel }
        return (atOrBelowLevel.isEmpty ? candidates : atOrBelowLevel).min { lhs, rhs in
            let lhsDistance = abs(lhs.minimumLevel - partyLevel)
            let rhsDistance = abs(rhs.minimumLevel - partyLevel)
            return lhsDistance == rhsDistance ? lhs.routeOrder < rhs.routeOrder : lhsDistance < rhsDistance
        }
    }

    static func activityPlan(
        route: [RouteCheckpoint],
        dispositions: [String: CheckpointDisposition],
        selectedId: String?,
        partyLevel: Int
    ) -> LevelActivityPlan? {
        guard let recommendation = nextCheckpoint(
            route: route, dispositions: dispositions, selectedId: selectedId, partyLevel: partyLevel
        ) else { return nil }
        let pending = route.filter { (dispositions[$0.id] ?? .pending) == .pending }
        let phase = routePhase(recommendation)
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(dispositions.compactMap { $0.value != .pending ? $0.key : nil })
        let eligible = phasePending.filter { checkpoint in
            checkpoint.prerequisites.allSatisfy { resolved.contains($0) }
        }
        let safeXP = eligible
            .filter { $0.importance == "minor" && $0.minimumLevel <= partyLevel }
            .sorted { $0.routeOrder < $1.routeOrder }
        let major = phasePending
            .filter { $0.importance == "major" }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.minimumLevel - partyLevel)
                let rhsDistance = abs(rhs.minimumLevel - partyLevel)
                return lhsDistance == rhsDistance ? lhs.routeOrder < rhs.routeOrder : lhsDistance < rhsDistance
            }
        let activityLabel: String
        let gateAdvice: String
        if recommendation.minimumLevel > partyLevel {
            activityLabel = "EARN XP FIRST"
            gateAdvice = "This needs L\(recommendation.minimumLevel). Do quests and the safe fights in \(routePhaseName(recommendation)), then come back."
        } else if recommendation.importance == "major" {
            activityLabel = "MAIN FIGHT"
            gateAdvice = "You're at level. Review the fight plan, then start it on your terms."
        } else {
            activityLabel = "SAFE XP"
            if let major, major.minimumLevel > partyLevel {
                gateAdvice = "Safe at your level — builds XP toward \(major.name) (L\(major.minimumLevel))."
            } else {
                gateAdvice = "Safe at your level. Clear it before the main fight."
            }
        }
        return LevelActivityPlan(
            activityLabel: activityLabel,
            phaseName: routePhaseName(recommendation),
            recommendation: recommendation,
            safeXP: safeXP,
            coreChallenge: major,
            gateAdvice: gateAdvice
        )
    }

    static func routePhase(_ checkpoint: RouteCheckpoint) -> Int {
        switch checkpoint.region {
        case "Nautiloid": return 0
        case "Underdark": return 2
        case "Grymforge": return 3
        case "Crèche Y'llek": return 4
        default: return 1
        }
    }

    static func routePhaseName(_ checkpoint: RouteCheckpoint) -> String {
        if checkpoint.id.hasPrefix("act3-") { return checkpoint.region }
        switch routePhase(checkpoint) {
        case 0: return "Nautiloid"
        case 1: return "Wilderness cleanup"
        case 2: return "Underdark"
        case 3: return "Grymforge"
        default: return "Mountain Pass / Crèche"
        }
    }

    static func actTwoBlockers(route: [RouteCheckpoint], dispositions: [String: CheckpointDisposition]) -> [String] {
        routeConsequences(route: route, dispositions: dispositions)
    }

    static func routeConsequences(route: [RouteCheckpoint], dispositions: [String: CheckpointDisposition]) -> [String] {
        route.compactMap { checkpoint in
            let state = dispositions[checkpoint.id] ?? .pending
            guard !state.countsAsCompleted, checkpoint.importance == "major" || !checkpoint.irreversibleWarnings.isEmpty else { return nil }
            let prefix = state == .skipped ? "Skipped" : "Unresolved"
            return "\(prefix) — \(checkpoint.name): \(checkpoint.irreversibleWarnings.first ?? "major checkpoint unresolved")"
        }
    }
}
