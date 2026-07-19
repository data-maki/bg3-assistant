import XCTest
@testable import BG3HonorAssistant

final class GearLogicTests: XCTestCase {
    private func claim(_ memberId: String, name: String? = nil, items: Set<String>) -> GearLogic.GearClaim {
        GearLogic.GearClaim(memberId: memberId, memberName: name ?? memberId.capitalized, itemKeys: items)
    }

    func testOverrideWinsWhileItsTargetStillClaimsTheItem() {
        let claims = [
            claim("astarion", items: ["caustic-band"]),
            claim("karlach", items: ["caustic-band"]),
        ]
        XCTAssertEqual(
            GearLogic.assignments(claims: claims, overrides: ["caustic-band": "karlach"])["caustic-band"],
            "karlach"
        )
        // A stale override (target no longer claims) falls back to the default.
        XCTAssertEqual(
            GearLogic.assignments(claims: claims, overrides: ["caustic-band": "gale"])["caustic-band"],
            "astarion"
        )
    }

    func testContestedItemsDefaultToAlphabeticallyFirstClaimant() {
        let result = GearLogic.assignments(
            claims: [
                claim("karlach", items: ["caustic-band", "haste-helm"]),
                claim("astarion", items: ["caustic-band"]),
            ],
            overrides: [:]
        )
        XCTAssertEqual(result["caustic-band"], "astarion")
        XCTAssertEqual(result["haste-helm"], "karlach", "uncontested items go to their only claimant")
    }
}
