import XCTest
@testable import BG3HonorAssistant

final class PartyRosterTests: XCTestCase {
    func testUnrecruitedCompanionCanFillAnOpenPartySlot() {
        var run = HonorRun()
        run.normalizeRoster()

        guard let laezelID = run.roster?.first(where: { $0.name == "Lae'zel" })?.id else {
            return XCTFail("Lae'zel should exist after roster migration")
        }
        XCTAssertTrue(run.applyRosterStatus(.camp, memberID: laezelID))
        XCTAssertTrue(run.applyRosterStatus(.active, memberID: "minthara"))

        XCTAssertEqual(run.roster?.first { $0.name == "Lae'zel" }?.rosterStatus, .camp)
        XCTAssertEqual(run.roster?.first { $0.id == "minthara" }?.rosterStatus, .active)
        XCTAssertEqual(run.activeParty.count, 4)
    }
}
