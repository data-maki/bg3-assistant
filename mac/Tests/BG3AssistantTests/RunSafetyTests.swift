import XCTest
@testable import BG3HonorAssistant

final class RunSafetyTests: XCTestCase {
    private func step(
        id: String,
        order: Int,
        phaseOrder: Int = 1,
        kind: String = "exploration",
        minimumLevel: Int = 1,
        dependencies: [WalkthroughDependency] = []
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, order: order, phase: "Phase \(phaseOrder)", phaseOrder: phaseOrder,
            title: "Title \(id)", kind: kind, importance: "core", region: "Wilderness",
            area: "Area", minimumLevel: minimumLevel, summary: "", avoid: "", why: "",
            rewards: [], completionChecks: [], prerequisites: [], dependencies: dependencies,
            checkpointId: nil, markerId: nil, decision: nil, incident: nil,
            riskReward: nil, authority: "guide_fact", sourceLabel: "", sourceUrl: ""
        )
    }

    private func dependency(
        on stepId: String,
        kind: String,
        reason: String = "reason",
        requiredOutcome: String? = nil
    ) -> WalkthroughDependency {
        WalkthroughDependency(stepId: stepId, kind: kind, reason: reason, requiredOutcome: requiredOutcome)
    }

    private func checkpoint(
        id: String,
        routeOrder: Int,
        region: String = "Wilderness",
        minimumLevel: Int = 1,
        importance: String = "minor",
        irreversibleWarnings: [String] = [],
        prerequisites: [String] = []
    ) -> RouteCheckpoint {
        RouteCheckpoint(
            id: id, routeOrder: routeOrder, name: "Name \(id)", area: "Area", region: region,
            x: 0, y: 0, minimumLevel: minimumLevel, importance: importance, danger: "medium",
            enemies: "", advice: "", legendaryAction: nil, failureConditions: [],
            preparation: [], completionChecks: [], irreversibleWarnings: irreversibleWarnings,
            prerequisites: prerequisites, notes: [], honorDecisions: [],
            source: GuideSource(sheet: "Route", row: 1, url: "")
        )
    }

    // MARK: dependencyBlockers

    func testWarningOnlyDependencyNeverBlocks() {
        let target = step(id: "b", order: 2, dependencies: [dependency(on: "a", kind: "warning_only")])
        let blockers = RunSafety.dependencyBlockers(
            for: target, walkthrough: [step(id: "a", order: 1), target],
            walkthroughProgress: [:]
        )
        XCTAssertTrue(blockers.isEmpty)
    }

    func testCompletionRequiredBlocksUntilCompleted() {
        let target = step(id: "b", order: 2, dependencies: [dependency(on: "a", kind: "completion_required")])
        let walkthrough = [step(id: "a", order: 1), target]
        XCTAssertEqual(
            RunSafety.dependencyBlockers(for: target, walkthrough: walkthrough, walkthroughProgress: [:]),
            ["reason"]
        )
        XCTAssertTrue(
            RunSafety.dependencyBlockers(
                for: target, walkthrough: walkthrough, walkthroughProgress: ["a": .completed]
            ).isEmpty
        )
    }

    func testSkippedCompletionDependencyAsksForRevisit() {
        let target = step(id: "b", order: 2, dependencies: [dependency(on: "a", kind: "completion_required")])
        let blockers = RunSafety.dependencyBlockers(
            for: target, walkthrough: [step(id: "a", order: 1), target],
            walkthroughProgress: ["a": .skipped]
        )
        XCTAssertEqual(blockers, ["Revisit Title a — reason"])
    }

    func testOutcomeRequiredNeedsCompletionAndMatchingOutcome() {
        let target = step(
            id: "b", order: 2,
            dependencies: [dependency(on: "a", kind: "outcome_required", requiredOutcome: "Spared")]
        )
        let walkthrough = [step(id: "a", order: 1), target]
        XCTAssertFalse(
            RunSafety.dependencyBlockers(
                for: target, walkthrough: walkthrough,
                walkthroughProgress: ["a": .completed], walkthroughOutcomes: ["a": "Killed"]
            ).isEmpty
        )
        XCTAssertTrue(
            RunSafety.dependencyBlockers(
                for: target, walkthrough: walkthrough,
                walkthroughProgress: ["a": .completed], walkthroughOutcomes: ["a": "Spared"]
            ).isEmpty
        )
    }

    func testDefaultDependencyKindAcceptsAnyResolution() {
        let target = step(id: "b", order: 2, dependencies: [dependency(on: "a", kind: "soft")])
        let walkthrough = [step(id: "a", order: 1), target]
        XCTAssertFalse(
            RunSafety.dependencyBlockers(for: target, walkthrough: walkthrough, walkthroughProgress: [:]).isEmpty
        )
        XCTAssertTrue(
            RunSafety.dependencyBlockers(
                for: target, walkthrough: walkthrough, walkthroughProgress: ["a": .skipped]
            ).isEmpty
        )
    }

    // MARK: nextWalkthroughStep

    func testNextStepPicksEarliestPendingPhaseInOrder() {
        let walkthrough = [
            step(id: "p2", order: 10, phaseOrder: 2),
            step(id: "late", order: 5, phaseOrder: 1),
            step(id: "early", order: 1, phaseOrder: 1),
        ]
        let next = RunSafety.nextWalkthroughStep(
            walkthrough: walkthrough, walkthroughProgress: ["early": .completed],
            selectedCheckpointId: nil, partyLevel: 3
        )
        XCTAssertEqual(next?.id, "late")
    }

    func testNextStepSkipsDependencyBlockedSteps() {
        let blocked = step(
            id: "blocked", order: 1,
            dependencies: [dependency(on: "gate", kind: "completion_required")]
        )
        let walkthrough = [blocked, step(id: "free", order: 2), step(id: "gate", order: 3, phaseOrder: 2)]
        let next = RunSafety.nextWalkthroughStep(
            walkthrough: walkthrough, walkthroughProgress: [:],
            selectedCheckpointId: nil, partyLevel: 3
        )
        XCTAssertEqual(next?.id, "free")
    }

    func testNextStepPrefersAtLevelStepButFallsBackToFirstEligible() {
        let walkthrough = [
            step(id: "high", order: 1, minimumLevel: 5),
            step(id: "atLevel", order: 2, minimumLevel: 2),
        ]
        XCTAssertEqual(
            RunSafety.nextWalkthroughStep(
                walkthrough: walkthrough, walkthroughProgress: [:],
                selectedCheckpointId: nil, partyLevel: 3
            )?.id,
            "atLevel"
        )
        XCTAssertEqual(
            RunSafety.nextWalkthroughStep(
                walkthrough: walkthrough, walkthroughProgress: [:],
                selectedCheckpointId: nil, partyLevel: 1
            )?.id,
            "high"
        )
    }

    // MARK: nextCheckpoint

    func testSelectedCheckpointShortCircuits() {
        let route = [checkpoint(id: "a", routeOrder: 1), checkpoint(id: "b", routeOrder: 2)]
        let next = RunSafety.nextCheckpoint(
            route: route, dispositions: ["b": .completed], selectedId: "b", partyLevel: 1
        )
        XCTAssertEqual(next?.id, "b")
    }

    func testNextCheckpointRespectsPhaseThenLevelDistanceThenRouteOrder() {
        let route = [
            checkpoint(id: "underdark", routeOrder: 1, region: "Underdark"),
            checkpoint(id: "far", routeOrder: 3, minimumLevel: 4),
            checkpoint(id: "near", routeOrder: 2, minimumLevel: 3),
        ]
        let next = RunSafety.nextCheckpoint(route: route, dispositions: [:], selectedId: nil, partyLevel: 3)
        XCTAssertEqual(next?.id, "near", "wilderness phase precedes Underdark; closest at-level checkpoint wins")
    }

    func testNextCheckpointHonorsPrerequisites() {
        let route = [
            checkpoint(id: "locked", routeOrder: 1, prerequisites: ["key"]),
            checkpoint(id: "open", routeOrder: 2),
            checkpoint(id: "key", routeOrder: 3),
        ]
        XCTAssertEqual(
            RunSafety.nextCheckpoint(route: route, dispositions: [:], selectedId: nil, partyLevel: 1)?.id,
            "open"
        )
        XCTAssertEqual(
            RunSafety.nextCheckpoint(
                route: route, dispositions: ["key": .completed], selectedId: nil, partyLevel: 1
            )?.id,
            "locked"
        )
    }

    // MARK: actTwoBlockers

    func testActTwoBlockersReportSkippedAndUnresolvedMajors() {
        let route = [
            checkpoint(id: "done", routeOrder: 1, importance: "major"),
            checkpoint(id: "skipped", routeOrder: 2, importance: "major", irreversibleWarnings: ["Point of no return"]),
            checkpoint(id: "pendingMinor", routeOrder: 3),
            checkpoint(id: "pendingWarned", routeOrder: 4, irreversibleWarnings: ["Warned"]),
        ]
        let blockers = RunSafety.actTwoBlockers(
            route: route, dispositions: ["done": .completed, "skipped": .skipped]
        )
        XCTAssertEqual(blockers, [
            "Skipped — Name skipped: Point of no return",
            "Unresolved — Name pendingWarned: Warned",
        ])
    }

    func testActThreeCheckpointUsesItsRegionAsThePhaseName() {
        let checkpoint = checkpoint(id: "act3-iron-throne", routeOrder: 1, region: "Iron Throne")

        XCTAssertEqual(RunSafety.routePhaseName(checkpoint), "Iron Throne")
    }

    // MARK: caughtUp (mid-run adoption) semantics

    func testCaughtUpCountsAsCompleted() {
        XCTAssertTrue(CheckpointDisposition.caughtUp.countsAsCompleted)
        XCTAssertTrue(CheckpointDisposition.completed.countsAsCompleted)
        XCTAssertFalse(CheckpointDisposition.pending.countsAsCompleted)
        XCTAssertFalse(CheckpointDisposition.skipped.countsAsCompleted)
    }

    func testCaughtUpSatisfiesCompletionRequiredDependency() {
        let target = step(id: "b", order: 2, dependencies: [dependency(on: "a", kind: "completion_required")])
        let blockers = RunSafety.dependencyBlockers(
            for: target, walkthrough: [step(id: "a", order: 1), target],
            walkthroughProgress: ["a": .caughtUp]
        )
        XCTAssertTrue(blockers.isEmpty)
    }

    func testCaughtUpSatisfiesOutcomeRequiredDependencyWithoutRecordedOutcome() {
        // Catch-up assumes the guide's recommended path happened; no outcome
        // is recorded, and the dependency must not nag forever.
        let target = step(
            id: "b", order: 2,
            dependencies: [dependency(on: "a", kind: "outcome_required", requiredOutcome: "Spared")]
        )
        let blockers = RunSafety.dependencyBlockers(
            for: target, walkthrough: [step(id: "a", order: 1), target],
            walkthroughProgress: ["a": .caughtUp], walkthroughOutcomes: [:]
        )
        XCTAssertTrue(blockers.isEmpty)
    }

    func testRouteConsequencesIgnoreCaughtUpCheckpoints() {
        let route = [
            checkpoint(id: "adopted", routeOrder: 1, importance: "major", irreversibleWarnings: ["Point of no return"]),
            checkpoint(id: "open", routeOrder: 2, importance: "major"),
        ]
        let consequences = RunSafety.routeConsequences(
            route: route, dispositions: ["adopted": .caughtUp]
        )
        XCTAssertEqual(consequences, ["Unresolved — Name open: major checkpoint unresolved"])
    }

    func testNextStepRecommendsFirstPendingAfterCaughtUpBlock() {
        let walkthrough = [
            step(id: "a", order: 1),
            step(id: "b", order: 2),
            step(id: "c", order: 3),
        ]
        let next = RunSafety.nextWalkthroughStep(
            walkthrough: walkthrough,
            walkthroughProgress: ["a": .caughtUp, "b": .caughtUp],
            selectedCheckpointId: nil, partyLevel: 3
        )
        XCTAssertEqual(next?.id, "c")
    }
}
