import XCTest
@testable import BG3HonorAssistant

final class ActLedgerTests: XCTestCase {
    func testOnlyPastActLedgersAreLocked() {
        var run = HonorRun()
        run.selectedAct = 2

        XCTAssertTrue(run.actLedgerIsLocked(1))
        XCTAssertFalse(run.actLedgerIsLocked(2))
        XCTAssertFalse(run.actLedgerIsLocked(3))
    }

    func testFinalActRecordLocksActThreeLedger() {
        var run = HonorRun()
        run.selectedAct = 3
        run.finalActRecord = ActTransitionRecord(
            fromAct: 3,
            toAct: 3,
            gearReview: ["item": .obtained],
            unresolvedRouteCount: 0,
            advancedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertTrue(run.actLedgerIsLocked(3))
        XCTAssertEqual(run.lockedActGearReviewStatus(for: "item", in: 3), .obtained)
    }
}
