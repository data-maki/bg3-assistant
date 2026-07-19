import XCTest
@testable import BG3HonorAssistant

final class HintTests: XCTestCase {
    func testHintRawValuesStayStable() {
        // Raw values persist in AssistantSettings.seenHints; renaming one
        // would re-show a hint every user has already dismissed.
        XCTAssertEqual(Set(HintID.allCases.map(\.rawValue)), ["peekBasics", "plannerMap", "fightTools"])
    }

    func testHintBandGrowsThePanelExceptDuringOnboarding() {
        let reference = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let plain = OverlayMetrics.panelSize(expanded: false, reference: reference)
        let hinted = OverlayMetrics.panelSize(expanded: false, reference: reference, hint: true)
        XCTAssertEqual(hinted.width, plain.width)
        XCTAssertEqual(hinted.height, plain.height + OverlayMetrics.hintBand)

        let expandedPlain = OverlayMetrics.panelSize(expanded: true, reference: reference, tab: .route)
        let expandedHinted = OverlayMetrics.panelSize(expanded: true, reference: reference, tab: .route, hint: true)
        XCTAssertEqual(expandedHinted.height, expandedPlain.height + OverlayMetrics.hintBand)

        XCTAssertEqual(
            OverlayMetrics.panelSize(expanded: false, reference: reference, onboarding: true, hint: true),
            OverlayMetrics.onboardingSize(for: reference)
        )
    }
}
