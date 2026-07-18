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

    func testLockedLedgerUsesTransitionSnapshot() {
        var run = HonorRun()
        run.selectedAct = 2
        run.actGearReview = [1: ["item": .obtained]]
        run.actTransitions = [
            ActTransitionRecord(
                fromAct: 1,
                toAct: 2,
                gearReview: ["item": .missed],
                unresolvedRouteCount: 0,
                advancedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        XCTAssertEqual(run.lockedActGearReviewStatus(for: "item", in: 1), .missed)
        XCTAssertNil(run.lockedActGearReviewStatus(for: "item", in: 2))
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
