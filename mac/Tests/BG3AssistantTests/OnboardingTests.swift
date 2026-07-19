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

    // MARK: - Catch-up ledger

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

    func testCatchUpUnknownCheckpointYieldsNil() {
        XCTAssertNil(CatchUp.ledger(markingThrough: "nope", walkthrough: [step(id: "s1", order: 1)], existing: [:]))
        XCTAssertEqual(CatchUp.markedCount(markingThrough: "nope", walkthrough: [], existing: [:]), 0)
    }

    // MARK: - Settings persistence

    func testSeenStateRoundTripsThroughStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "onboarding-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        var finished = store.loadSettings()
        finished.onboardingSeenVersion = OnboardingStep.version
        finished.seenHints = ["peekBasics", "plannerMap"]
        try store.saveSettings(finished)

        let reloaded = RunStore(baseDirectory: tempDir).loadSettings()
        XCTAssertEqual(reloaded.onboardingSeenVersion, OnboardingStep.version)
        XCTAssertEqual(reloaded.seenHints, ["peekBasics", "plannerMap"])
    }
}
