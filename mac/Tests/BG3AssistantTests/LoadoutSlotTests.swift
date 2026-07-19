import XCTest
@testable import BG3HonorAssistant

final class LoadoutSlotTests: XCTestCase {
    func testTorchesClassifyByItemNameDespiteMeleeSlot() {
        XCTAssertEqual(LoadoutSlot.classify("Melee", item: "Torch x2"), .torch)
        XCTAssertEqual(LoadoutSlot.classify("Melee", item: "torch"), .torch)
    }

    func testNonTorchWeaponsKeepSlotStringClassification() {
        XCTAssertEqual(LoadoutSlot.classify("Melee", item: "Everburn Blade"), .mainHand)
        XCTAssertEqual(LoadoutSlot.classify("Melee / stat stick", item: "Staff"), .mainHand)
        XCTAssertEqual(LoadoutSlot.classify("Summoned off-hand weapon", item: "Flame Blade"), .offHand)
        XCTAssertEqual(LoadoutSlot.classify("Ranged", item: "Bow of Awareness"), .ranged)
    }

    func testArmourAndJewellerySlotsUnchanged() {
        XCTAssertEqual(LoadoutSlot.classify("Ring", item: "Caustic Band"), .rings)
        XCTAssertEqual(LoadoutSlot.classify("Head", item: "Haste Helm"), .helmet)
        XCTAssertEqual(LoadoutSlot.classify("Chest", item: "Breastplate +1"), .armour)
    }

    // MARK: DollCell

    private func ring(_ name: String) -> BuildGear {
        BuildGear(
            item: name, slot: "Ring", priority: "Core", act: 1, region: "Druid Grove",
            acquisition: "", why: "", source: "",
            minimumLevel: nil, requirement: nil, acquire: nil
        )
    }

    func testRingFieldsSplitFirstAndRemainingRings() {
        let grouped: [LoadoutSlot: [BuildGear]] = [.rings: [ring("Caustic Band"), ring("Ring of Colour Spray")]]
        XCTAssertEqual(DollCell(slot: .rings, field: 0).items(in: grouped).map(\.item), ["Caustic Band"])
        XCTAssertEqual(DollCell(slot: .rings, field: 1).items(in: grouped).map(\.item), ["Ring of Colour Spray"])
    }

    func testSecondRingFieldEmptyWithSingleRing() {
        let grouped: [LoadoutSlot: [BuildGear]] = [.rings: [ring("Caustic Band")]]
        XCTAssertEqual(DollCell(slot: .rings, field: 0).items(in: grouped).map(\.item), ["Caustic Band"])
        XCTAssertTrue(DollCell(slot: .rings, field: 1).items(in: grouped).isEmpty)
    }

    func testRarityClassificationDoesNotTreatVeryRareAsRare() {
        XCTAssertEqual(GearRarity(effect: "A very rare helmet."), .veryRare)
        XCTAssertEqual(GearRarity(effect: "A rare ring."), .rare)
        XCTAssertEqual(GearRarity(effect: "An uncommon amulet."), .uncommon)
        XCTAssertEqual(GearRarity(effect: nil), .common)
    }

    func testRegionClassificationGroupsRelatedLocations() {
        XCTAssertEqual(GearLogic.regionCluster(for: "Druid Grove / Riverside Teahouse"), .wilderness)
        XCTAssertEqual(GearLogic.regionCluster(for: "Selûnite Outpost, Underdark"), .underdark)
        XCTAssertEqual(GearLogic.regionCluster(for: "Crèche Y'llek, Inquisitor's Chamber"), .mountainPass)
        XCTAssertEqual(GearLogic.regionCluster(for: "Anywhere"), .other)
    }

    func testRouteRankOrdersActOneRegionsAndSortsUnknownLast() {
        let grove = GearLogic.routeRank(region: "Druid Grove", act: 1)
        let underdark = GearLogic.routeRank(region: "Underdark", act: 1)
        let creche = GearLogic.routeRank(region: "Crèche Y'llek", act: 1)
        let unknown = GearLogic.routeRank(region: "Nowhere Special", act: 1)
        XCTAssertLessThan(grove, underdark)
        XCTAssertLessThan(underdark, creche)
        XCTAssertLessThan(creche, unknown)
    }
}
