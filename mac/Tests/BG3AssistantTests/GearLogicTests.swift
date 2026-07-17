import XCTest
@testable import BG3HonorAssistant

final class GearLogicTests: XCTestCase {
    private func step(
        id: String,
        order: Int,
        phaseOrder: Int = 1,
        area: String,
        region: String = "Wilderness"
    ) -> WalkthroughStep {
        WalkthroughStep(
            id: id, order: order, phase: "Phase \(phaseOrder)", phaseOrder: phaseOrder,
            title: id, kind: "exploration", importance: "core", region: region, area: area,
            minimumLevel: 1, summary: "", avoid: "", why: "", rewards: [],
            completionChecks: [], prerequisites: [], dependencies: [],
            checkpointId: nil, markerId: nil, decision: nil, incident: nil,
            riskReward: nil, authority: "guide_fact", sourceLabel: "", sourceUrl: ""
        )
    }

    private func gear(
        item: String = "Titanstring Bow",
        region: String = "Zhentarim Hideout",
        acquisition: String = "Buy from Brem",
        minimumLevel: Int? = nil,
        requirement: String? = nil,
        acquire: String? = nil
    ) -> BuildGear {
        BuildGear(
            item: item, slot: "Ranged", priority: "Core", act: 1, region: region,
            acquisition: acquisition, why: "", source: "",
            minimumLevel: minimumLevel, requirement: requirement, acquire: acquire
        )
    }

    // MARK: regionParts

    func testRegionPartsSplitsAndTrims() {
        XCTAssertEqual(
            GearLogic.regionParts("Druid Grove / Shattered Sanctum"),
            ["Druid Grove", "Shattered Sanctum"]
        )
        XCTAssertEqual(GearLogic.regionParts("Goblin Camp"), ["Goblin Camp"])
        XCTAssertEqual(GearLogic.regionParts("  "), [])
    }

    // MARK: matchingSteps

    func testMatchingStepsMatchesAreaCaseInsensitivelyInRouteOrder() {
        let walkthrough = [
            step(id: "late", order: 9, area: "Zhentarim Hideout"),
            step(id: "early", order: 2, area: "zhentarim hideout"),
            step(id: "unrelated", order: 5, area: "Emerald Grove"),
        ]
        let matched = GearLogic.matchingSteps(for: gear(), in: walkthrough)
        XCTAssertEqual(matched.map(\.id), ["early", "late"])
    }

    func testMatchingStepsMatchesWhenGearRegionContainsStepArea() {
        let walkthrough = [step(id: "hideout", order: 1, area: "Hideout")]
        let matched = GearLogic.matchingSteps(for: gear(region: "Zhentarim Hideout"), in: walkthrough)
        XCTAssertEqual(matched.map(\.id), ["hideout"])
    }

    func testMatchingStepsMatchesSecondRegionPartAgainstStepRegion() {
        let walkthrough = [step(id: "sanctum", order: 3, area: "Chapel", region: "Shattered Sanctum")]
        let matched = GearLogic.matchingSteps(
            for: gear(region: "Druid Grove / Shattered Sanctum"),
            in: walkthrough
        )
        XCTAssertEqual(matched.map(\.id), ["sanctum"])
    }

    func testMatchingStepsEmptyRegionMatchesNothing() {
        let walkthrough = [step(id: "any", order: 1, area: "Anywhere")]
        XCTAssertEqual(GearLogic.matchingSteps(for: gear(region: " "), in: walkthrough), [])
    }

    // MARK: pathRows

    func testPathRowsOrderIsLevelGateStepsInfoAcquisition() {
        let walkthrough = [
            step(id: "trust", order: 2, area: "Zhentarim Hideout"),
            step(id: "find", order: 1, area: "Zhentarim Hideout"),
        ]
        let rows = GearLogic.pathRows(
            gear: gear(minimumLevel: 5, requirement: "Needs Zarys's trust"),
            memberLevel: 4,
            walkthrough: walkthrough,
            dispositions: ["find": .completed]
        )
        guard rows.count == 5 else { return XCTFail("expected 5 rows, got \(rows)") }
        XCTAssertEqual(rows[0], .levelGate(required: 5, partyLevel: 4))
        XCTAssertEqual(rows[1], .step(walkthrough[1], done: true))
        XCTAssertEqual(rows[2], .step(walkthrough[0], done: false))
        XCTAssertEqual(rows[3], .info("Needs Zarys's trust"))
        XCTAssertEqual(rows[4], .acquisition("Buy from Brem"))
    }

    func testPathRowsOmitsLevelGateWhenMemberMeetsMinimum() {
        let rows = GearLogic.pathRows(
            gear: gear(minimumLevel: 3), memberLevel: 3, walkthrough: [], dispositions: [:]
        )
        XCTAssertEqual(rows, [.acquisition("Buy from Brem")])
    }

    func testPathRowsFallbackIsAcquisitionOnlyAndPrefersWikiAcquireText() {
        let rows = GearLogic.pathRows(
            gear: gear(acquire: "Purchased from Brem in the hideout"),
            memberLevel: 4, walkthrough: [], dispositions: [:]
        )
        XCTAssertEqual(rows, [.acquisition("Purchased from Brem in the hideout")])
    }

    func testSkippedStepsCountAsNotDone() {
        let walkthrough = [step(id: "find", order: 1, area: "Zhentarim Hideout")]
        let rows = GearLogic.pathRows(
            gear: gear(), memberLevel: 4, walkthrough: walkthrough,
            dispositions: ["find": .skipped]
        )
        XCTAssertEqual(rows.first, .step(walkthrough[0], done: false))
    }

    // MARK: pickupsByPhase

    func testPickupsBucketByFirstMatchedStepPhaseAndUnmatchedGoToOther() {
        let walkthrough = [
            step(id: "grove", order: 1, phaseOrder: 1, area: "Druid Grove"),
            step(id: "hideout", order: 8, phaseOrder: 3, area: "Zhentarim Hideout"),
        ]
        let bow = GearLogic.Pickup(gear: gear(), memberId: "m1", memberName: "Astarion")
        let plate = GearLogic.Pickup(
            gear: gear(item: "Breastplate +1", region: "Druid Grove"),
            memberId: "m2", memberName: "Lae'zel"
        )
        let lost = GearLogic.Pickup(
            gear: gear(item: "Caustic Band", region: "Myconid Colony"),
            memberId: "m1", memberName: "Astarion"
        )
        let result = GearLogic.pickupsByPhase([bow, plate, lost], walkthrough: walkthrough)
        XCTAssertEqual(result.byPhase[3], [bow])
        XCTAssertEqual(result.byPhase[1], [plate])
        XCTAssertEqual(result.other, [lost])
    }

    // MARK: priorityRank

    func testPriorityRankOrdersRequiredBeforeCoreAndUnknownLast() {
        XCTAssertLessThan(GearLogic.priorityRank("Required"), GearLogic.priorityRank("Core"))
        XCTAssertLessThan(GearLogic.priorityRank("Core"), GearLogic.priorityRank("Optional"))
        XCTAssertEqual(GearLogic.priorityRank("Nonsense"), 99)
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
