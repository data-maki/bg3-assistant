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

    func testLocalModelCapabilitiesAreExplicit() {
        XCTAssertEqual(AIProvider.localGemma.ollamaModel, "gemma4:12b")
        XCTAssertEqual(AIProvider.localGemma.modelDownloadSize, "7.6 GB")
        XCTAssertTrue(AIProvider.localGemma.supportsImages)

        XCTAssertEqual(AIProvider.localQwen.ollamaModel, "qwen3:4b")
        XCTAssertEqual(AIProvider.localQwen.modelDownloadSize, "2.5 GB")
        XCTAssertFalse(AIProvider.localQwen.supportsImages)
    }

    func testOllamaImageIsAttachedToLastMessage() throws {
        let encoded = AssistantAIClient.ollamaMessages(
            [
                AssistantAIMessage(role: "system", content: "Use the guide."),
                AssistantAIMessage(role: "user", content: "What is on screen?"),
            ],
            imageData: Data([1, 2, 3])
        )

        XCTAssertNil(encoded[0]["images"])
        XCTAssertEqual(try XCTUnwrap(encoded[1]["images"] as? [String]), ["AQID"])
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
