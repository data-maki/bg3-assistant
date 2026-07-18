import XCTest
@testable import BG3HonorAssistant

final class OnboardingTests: XCTestCase {
    func testStepOrderAndNavigation() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .peek, .planner, .party, .chat])
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertTrue(OnboardingStep.chat.isLast)
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertNil(OnboardingStep.chat.next)

        var walked: [OnboardingStep] = []
        var cursor: OnboardingStep? = .welcome
        while let step = cursor {
            walked.append(step)
            cursor = step.next
        }
        XCTAssertEqual(walked, OnboardingStep.allCases)
        for step in OnboardingStep.allCases where !step.isLast {
            XCTAssertEqual(step.next?.previous, step)
        }
    }

    func testStepContentIsComplete() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.intro.isEmpty)
            XCTAssertGreaterThanOrEqual(step.facts.count, 3)
            XCTAssertTrue(step.facts.allSatisfy { !$0.text.isEmpty && !$0.glyph.isEmpty })
            XCTAssertEqual(step.stepNumber, step.rawValue + 1)
        }
        XCTAssertEqual(OnboardingStep.chat.primaryActionTitle, "Start Adventuring")
        for step in OnboardingStep.allCases.dropLast() {
            XCTAssertEqual(step.primaryActionTitle, "Continue")
        }
        XCTAssertEqual(OnboardingStep.party.handoff, .party)
        XCTAssertEqual(OnboardingStep.chat.handoff, .settings)
        XCTAssertNil(OnboardingStep.welcome.handoff)
        XCTAssertNil(OnboardingStep.peek.handoff)
        XCTAssertNil(OnboardingStep.planner.handoff)
    }

    func testSettingsRowsWithoutTourFlagStillDecode() throws {
        let legacy = try JSONDecoder().decode(
            AssistantSettings.self,
            from: Data(#"{"overlayDensity":"Reference"}"#.utf8)
        )
        XCTAssertEqual(legacy.overlayDensity, OverlayDensity.reference.rawValue)
        XCTAssertNil(legacy.onboardingSeenVersion)
        XCTAssertNil(AssistantSettings.migrating().onboardingSeenVersion)
    }

    func testSeenVersionRoundTripsThroughStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "onboarding-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        // First load persists a migrated row without the tour key (encoders
        // drop nil optionals) — exactly the legacy shape older builds wrote.
        XCTAssertNil(store.loadSettings().onboardingSeenVersion)
        XCTAssertNil(RunStore(baseDirectory: tempDir).loadSettings().onboardingSeenVersion)

        var finished = store.loadSettings()
        finished.onboardingSeenVersion = OnboardingStep.version
        try store.saveSettings(finished)
        let reloaded = RunStore(baseDirectory: tempDir).loadSettings()
        XCTAssertEqual(reloaded.onboardingSeenVersion, OnboardingStep.version)
        XCTAssertEqual(reloaded.overlayDensity, finished.overlayDensity)
    }

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
