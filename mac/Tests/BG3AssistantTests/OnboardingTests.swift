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

    // MARK: - Branching navigation

    func testFreshRunSkipsCatchUp() {
        XCTAssertEqual(OnboardingStep.steps(for: .fresh), [.welcome, .party, .ready])
        XCTAssertEqual(OnboardingStep.steps(for: .midRun), [.welcome, .party, .catchUp, .ready])
        XCTAssertNil(OnboardingStep.catchUp.next(for: .fresh))
        XCTAssertNil(OnboardingStep.catchUp.previous(for: .fresh))
    }

    func testNavigationRoundTripsInBothModes() {
        for mode in [OnboardingMode.fresh, .midRun] {
            let steps = OnboardingStep.steps(for: mode)
            var walked: [OnboardingStep] = []
            var cursor: OnboardingStep? = steps.first
            while let current = cursor {
                walked.append(current)
                cursor = current.next(for: mode)
            }
            XCTAssertEqual(walked, steps)
            XCTAssertNil(steps.first?.previous(for: mode))
            XCTAssertNil(steps.last?.next(for: mode))
            for candidate in steps.dropFirst() {
                XCTAssertEqual(candidate.previous(for: mode)?.next(for: mode), candidate)
            }
            for (offset, candidate) in steps.enumerated() {
                XCTAssertEqual(candidate.stepNumber(for: mode), offset + 1)
            }
            XCTAssertEqual(OnboardingStep.stepCount(for: mode), steps.count)
        }
    }

    func testStepContentIsComplete() {
        XCTAssertEqual(OnboardingStep.version, 2)
        for mode in [OnboardingMode.fresh, .midRun] {
            for candidate in OnboardingStep.steps(for: mode) {
                XCTAssertFalse(candidate.title.isEmpty)
                XCTAssertFalse(candidate.intro.isEmpty)
            }
        }
        // The fork advances through its own buttons; every other step has a
        // primary action, and the wizard ends on "Start Adventuring".
        XCTAssertNil(OnboardingStep.welcome.primaryActionTitle(for: .fresh))
        XCTAssertEqual(OnboardingStep.ready.primaryActionTitle(for: .fresh), "Start Adventuring")
        XCTAssertEqual(OnboardingStep.catchUp.primaryActionTitle(for: .midRun), "Catch Up & Continue")
        XCTAssertGreaterThanOrEqual(OnboardingStep.ready.facts.count, 3)
        XCTAssertTrue(OnboardingStep.ready.facts.allSatisfy { !$0.text.isEmpty && !$0.glyph.isEmpty })
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

    func testCatchUpMarkedCountExcludesResolvedSteps() {
        let walkthrough = [
            step(id: "s1", order: 1, checkpointId: "cp1"),
            step(id: "s2", order: 2),
            step(id: "s3", order: 3, checkpointId: "cp2"),
        ]
        XCTAssertEqual(
            CatchUp.markedCount(markingThrough: "cp2", walkthrough: walkthrough, existing: ["s1": .completed]),
            2
        )
    }

    // MARK: - Settings persistence

    func testSettingsRowsWithoutNewFlagsStillDecode() throws {
        let legacy = try JSONDecoder().decode(
            AssistantSettings.self,
            from: Data(#"{"overlayDensity":"Reference","onboardingSeenVersion":1}"#.utf8)
        )
        XCTAssertEqual(legacy.overlayDensity, OverlayDensity.reference.rawValue)
        XCTAssertEqual(legacy.onboardingSeenVersion, 1)
        XCTAssertNil(legacy.onboardingCompleted)
        XCTAssertNil(legacy.seenHints)
    }

    func testCompletionAndHintsRoundTripThroughStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "onboarding-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        XCTAssertNil(store.loadSettings().onboardingCompleted)

        var finished = store.loadSettings()
        finished.onboardingSeenVersion = OnboardingStep.version
        finished.onboardingCompleted = true
        finished.seenHints = ["peekBasics", "plannerMap"]
        try store.saveSettings(finished)

        let reloaded = RunStore(baseDirectory: tempDir).loadSettings()
        XCTAssertEqual(reloaded.onboardingSeenVersion, OnboardingStep.version)
        XCTAssertEqual(reloaded.onboardingCompleted, true)
        XCTAssertEqual(reloaded.seenHints, ["peekBasics", "plannerMap"])
    }

    // MARK: - Panel metrics

    func testOnboardingPanelSizeIsStableAndDistinct() {
        let references = [
            CGRect(x: 0, y: 0, width: 1280, height: 800),
            CGRect(x: 0, y: 0, width: 1728, height: 1080),
            CGRect(x: 0, y: 0, width: 3440, height: 1440),
        ]
        for reference in references {
            let size = OverlayMetrics.onboardingSize(for: reference)
            XCTAssertTrue((430...520).contains(size.width))
            XCTAssertTrue((470...540).contains(size.height))
            for expanded in [true, false] {
                for density in OverlayDensity.allCases {
                    for tab in PlannerTab.allCases {
                        XCTAssertEqual(
                            OverlayMetrics.panelSize(
                                expanded: expanded, reference: reference, tab: tab,
                                density: density, moreContextExpanded: expanded, onboarding: true
                            ),
                            size
                        )
                    }
                }
            }
            // Non-onboarding callers keep their sizes.
            XCTAssertEqual(
                OverlayMetrics.panelSize(expanded: true, reference: reference, tab: .route),
                OverlayMetrics.expandedSize(for: reference, tab: .route)
            )
            XCTAssertEqual(
                OverlayMetrics.panelSize(expanded: false, reference: reference, density: .minimal),
                OverlayMetrics.collapsedSize(for: reference, density: .minimal)
            )
        }
    }
}
