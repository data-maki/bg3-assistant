import XCTest
@testable import BG3HonorAssistant

final class GearLogicTests: XCTestCase {
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

    func testAssignmentTieBreaksAlphabeticallyByBuildName() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: 100, items: ["caustic-band"]),
                claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
            ],
            overrides: [:]
        )
        XCTAssertEqual(result["caustic-band"], "astarion")  // "Assassin" < "Zerker"
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

    func testStaleOverrideFallsBackToRecency() {
        // Override points at someone who no longer wants (or has) the item.
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
                claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
            ],
            overrides: ["caustic-band": "gale"]
        )
        XCTAssertEqual(result["caustic-band"], "astarion")
    }

    func testUncontestedItemsAssignToTheirOnlyClaimant() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: 200, items: ["haste-helm"]),
                claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
            ],
            overrides: [:]
        )
        XCTAssertEqual(result["haste-helm"], "karlach")
        XCTAssertEqual(result["caustic-band"], "astarion")
    }

    func testMissingAssignmentDateSortsLast() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", build: "Zerker", at: nil, items: ["caustic-band"]),
                claim("astarion", build: "Assassin", at: 500, items: ["caustic-band"]),
            ],
            overrides: [:]
        )
        XCTAssertEqual(result["caustic-band"], "astarion")
    }
}
