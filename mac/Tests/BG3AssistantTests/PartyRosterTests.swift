import XCTest
@testable import BG3HonorAssistant

final class PartyRosterTests: XCTestCase {
    func testMigrationAddsDarkUrgeToCamp() {
        var run = HonorRun()

        run.migrateLegacyPartySlots()

        let darkUrge = run.roster?.first { $0.id == "dark-urge" }
        XCTAssertEqual(darkUrge?.name, "Dark Urge")
        XCTAssertEqual(darkUrge?.className, "Sorcerer")
        XCTAssertEqual(darkUrge?.rosterStatus, .camp)
        XCTAssertFalse(darkUrge?.isCustom ?? true)
    }

    func testUnrecruitedCompanionCanFillAnOpenPartySlot() {
        var run = HonorRun()
        run.migrateLegacyPartySlots()

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
