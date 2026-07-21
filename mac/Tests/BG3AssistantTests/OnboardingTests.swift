import XCTest
@testable import BG3HonorAssistant

final class OnboardingTests: XCTestCase {
    private func step(id: String, order: Int, checkpointId: String? = nil) -> WalkthroughStep {
        WalkthroughStep(
            id: id, order: order, phase: "Phase", phaseOrder: 1,
            title: "Title \(id)", kind: "exploration", importance: "core", region: "Wilderness",
            area: "Area", minimumLevel: 1, summary: "", avoid: "", why: "",
            rewards: [], completionChecks: [], prerequisites: [], dependencies: [],
            checkpointId: checkpointId, markerId: nil, decision: nil, incident: nil,
            riskReward: nil, authority: "guide_fact", sourceLabel: "", sourceUrl: ""
        )
    }

    func testProviderSetupIsRequiredForBothOnboardingPaths() {
        XCTAssertEqual(OnboardingStep.steps(for: .fresh), [.welcome, .ai, .party, .ready])
        XCTAssertEqual(OnboardingStep.steps(for: .midRun), [.welcome, .ai, .party, .catchUp, .ready])
    }

    func testCatchUpMarksThroughLandmarkInclusive() throws {
        let walkthrough = [
            step(id: "s1", order: 1, checkpointId: "cp1"),
            step(id: "s2", order: 2),
            step(id: "s3", order: 3, checkpointId: "cp2"),
            step(id: "s4", order: 4),
        ]
        let ledger = try XCTUnwrap(CatchUp.ledger(markingThrough: "cp2", walkthrough: walkthrough, existing: [:]))
        XCTAssertEqual(ledger["s1"], .caughtUp)
        XCTAssertEqual(ledger["s2"], .caughtUp)
        XCTAssertEqual(ledger["s3"], .caughtUp)
        XCTAssertNil(ledger["s4"])
    }

    func testCatchUpPreservesExplicitHistory() throws {
        let walkthrough = [
            step(id: "s1", order: 1, checkpointId: "cp1"),
            step(id: "s2", order: 2, checkpointId: "cp2"),
        ]
        let ledger = try XCTUnwrap(CatchUp.ledger(
            markingThrough: "cp2", walkthrough: walkthrough,
            existing: ["s1": .skipped]
        ))
        XCTAssertEqual(ledger["s1"], .skipped)
        XCTAssertEqual(ledger["s2"], .caughtUp)
    }
}
