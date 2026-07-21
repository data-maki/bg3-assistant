import XCTest
@testable import BG3HonorAssistant

final class GearLogicTests: XCTestCase {
    func testLoadoutClassifiesCapeInstrumentAndTorchOutsideEquipmentGrid() {
        XCTAssertEqual(LoadoutSlot.classify("Cloak", item: "Thunderskin Cloak"), .cloak)
        XCTAssertEqual(LoadoutSlot.classify("Instrument", item: "Spider's Lyre"), .instrument)
        XCTAssertEqual(LoadoutSlot.classify("Melee", item: "Torch x2"), .extras)
    }

    // MARK: assignments

    private func claim(
        _ memberId: String, build: String, at seconds: TimeInterval?, items: Set<String>
    ) -> GearLogic.GearClaim {
        GearLogic.GearClaim(
            memberId: memberId, memberName: memberId.capitalized, buildName: build,
            buildAssignedAt: seconds.map { Date(timeIntervalSince1970: $0) }, itemKeys: items
        )
    }

    func testAssignmentPrefersEarliestBuildAssignment() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
                claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
            ],
            overrides: [:]
        )
        XCTAssertEqual(result["caustic-band"], "astarion")
    }

    func testOverrideBeatsRecency() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
                claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
            ],
            overrides: ["caustic-band": "karlach"]
        )
        XCTAssertEqual(result["caustic-band"], "karlach")
    }

    func testRouteAndEquipmentTargetsReplaceEachOther() {
        var run = HonorRun()
        run.focusRoute(stepId: "grove", checkpointId: "grove-fight")

        run.focusGear(GearTarget(memberId: "tav", buildId: "cleric", gearId: "luminous-armour"))

        XCTAssertNil(run.focusedWalkthroughStepId)
        XCTAssertNil(run.selectedCheckpointId)
        XCTAssertEqual(run.gearTarget?.gearId, "luminous-armour")

        run.focusRoute(stepId: "goblin-camp", checkpointId: "minthara")

        XCTAssertNil(run.gearTarget)
        XCTAssertEqual(run.focusedWalkthroughStepId, "goblin-camp")
        XCTAssertEqual(run.selectedCheckpointId, "minthara")
    }
}
