import XCTest
@testable import BG3HonorAssistant

final class ManualBuildTests: XCTestCase {
    func testCatalogCoversEveryClassThroughLevelTwelve() {
        XCTAssertEqual(BG3ClassCatalog.definitions.count, 12)
        for definition in BG3ClassCatalog.definitions {
            XCTAssertEqual(Set(definition.levels.keys), Set(1...12), definition.name)
        }
    }

    func testWizardSeparatesCantripsFromLevelledSpells() throws {
        let wizard = try XCTUnwrap(BG3ClassCatalog.definition(named: "Wizard"))
        let level = try XCTUnwrap(wizard.levels[1])
        let cantrips = try XCTUnwrap(level.choices.first { $0.id == "cantrips" })
        let spells = try XCTUnwrap(level.choices.first { $0.id == "spells-1" })

        XCTAssertEqual(cantrips.maximumSelections, 3)
        XCTAssertEqual(spells.maximumSelections, 6)
        XCTAssertTrue(cantrips.options.contains { $0.name == "Acid Splash" })
        XCTAssertFalse(spells.options.contains { $0.name == "Acid Splash" })
        XCTAssertTrue(spells.options.contains { $0.name == "Magic Missile" })
        XCTAssertTrue(spells.options.contains { $0.name == "Shield" })
    }

    func testPatchEightSubclassesNeededByTankBuildAreAvailable() throws {
        let warlock = try XCTUnwrap(BG3ClassCatalog.definition(named: "Warlock"))
        let warlockSubclasses = try XCTUnwrap(warlock.levels[1]?.choices.first { $0.id == "subclass" })
        XCTAssertTrue(warlockSubclasses.options.contains { $0.name == "The Hexblade" })

        let wizard = try XCTUnwrap(BG3ClassCatalog.definition(named: "Wizard"))
        let wizardSubclasses = try XCTUnwrap(wizard.levels[2]?.choices.first { $0.id == "subclass" })
        XCTAssertTrue(wizardSubclasses.options.contains { $0.name == "Abjuration School" })
    }

    func testSubclassSpecificChoicesAreCompleteAndConditional() throws {
        let fighter = try XCTUnwrap(BG3ClassCatalog.definition(named: "Fighter"))
        let manoeuvres = try XCTUnwrap(fighter.levels[3]?.choices.first { $0.id == "manoeuvres-3" })
        XCTAssertEqual(manoeuvres.requiredSelection, "Battle Master")
        XCTAssertEqual(manoeuvres.maximumSelections, 3)
        XCTAssertTrue(manoeuvres.options.contains { $0.name == "Riposte" })
        XCTAssertTrue(manoeuvres.options.contains { $0.name == "Trip Attack" })

        let ranger = try XCTUnwrap(BG3ClassCatalog.definition(named: "Ranger"))
        let hunter = try XCTUnwrap(ranger.levels[3]?.choices.first { $0.id == "hunters-prey" })
        XCTAssertEqual(hunter.requiredSelection, "Hunter")
        XCTAssertEqual(Set(hunter.options.map(\.name)), ["Colossus Slayer", "Giant Killer", "Horde Breaker"])

        let barbarian = try XCTUnwrap(BG3ClassCatalog.definition(named: "Barbarian"))
        let heart = try XCTUnwrap(barbarian.levels[3]?.choices.first { $0.id == "bestial-heart" })
        XCTAssertEqual(heart.requiredSelection, "Wildheart")
        XCTAssertEqual(heart.options.count, 5)
    }

    func testAbilityImprovementRecordsItsAllocationAtTheSameLevel() throws {
        let wizard = try XCTUnwrap(BG3ClassCatalog.definition(named: "Wizard"))
        let allocation = try XCTUnwrap(wizard.levels[4]?.choices.first { $0.id == "ability-improvement-4" })

        XCTAssertEqual(allocation.requiredSelection, "Ability Improvement")
        XCTAssertTrue(allocation.requiresSelectionAtSameLevel)
        XCTAssertTrue(allocation.options.contains { $0.name == "+2 Intelligence" })
        XCTAssertTrue(allocation.options.contains { $0.name == "+1 Constitution / +1 Intelligence" })

        let initiate = try XCTUnwrap(wizard.levels[4]?.choices.first {
            $0.id == "magic-initiate-warlock-spell-4"
        })
        XCTAssertEqual(initiate.requiredSelection, "Magic Initiate: Warlock")
        XCTAssertTrue(initiate.requiresSelectionAtSameLevel)
        XCTAssertTrue(initiate.options.contains { $0.name == "Armour of Agathys" })
    }

    func testTankBuildSpellsAreInCurrentClassLists() {
        let warlock = BG3SpellCatalog.spells(for: "Warlock", through: 1)
        XCTAssertTrue(warlock.contains("Armour of Agathys"))

        let wizard = BG3SpellCatalog.spells(for: "Wizard", through: 6)
        for spell in ["Magic Missile", "Counterspell", "Glyph of Warding", "Fire Shield", "Hold Monster"] {
            XCTAssertTrue(wizard.contains(spell), spell)
        }
    }

    func testManualMulticlassLevelsAreCountedPerClass() {
        var plan = ManualBuildPlan.empty(name: "Immortal Tank", scores: .customDefault.clampedForPointBuy)
        plan.levels[0].className = "Warlock"
        for index in 1..<12 { plan.levels[index].className = "Wizard" }

        XCTAssertEqual(plan.classLevel(at: 1), 1)
        XCTAssertEqual(plan.classLevel(at: 2), 1)
        XCTAssertEqual(plan.classLevel(at: 3), 2)
        XCTAssertEqual(plan.classLevel(at: 12), 11)
        XCTAssertEqual(plan.classSummary, "Warlock 1 / Wizard 11")
    }

    func testClassChoiceContinuesUntilAnExplicitMulticlassBreak() {
        var plan = ManualBuildPlan.empty(name: "Tank", scores: .customDefault.clampedForPointBuy)

        plan.setClass("Warlock", at: 1)
        XCTAssertEqual(plan.levels.map(\.className), Array(repeating: "Warlock", count: 12))

        plan.setClass("Wizard", at: 2)
        XCTAssertEqual(plan.levels[0].className, "Warlock")
        XCTAssertEqual(Array(plan.levels.dropFirst().map(\.className)), Array(repeating: "Wizard", count: 11))

        plan.setClass("Fighter", at: 10)
        plan.setClass("Sorcerer", at: 5)
        XCTAssertEqual(plan.levels[4...8].map(\.className), Array(repeating: "Sorcerer", count: 5))
        XCTAssertEqual(plan.levels[9...11].map(\.className), Array(repeating: "Fighter", count: 3))
    }

    func testEveryCatalogChoiceHasAStableArtworkFilename() {
        let options = BG3ClassCatalog.definitions.flatMap { definition in
            definition.levels.values.flatMap { level in
                level.features + level.choices.flatMap(\.options)
            }
        }

        XCTAssertGreaterThan(options.count, 1_000)
        XCTAssertTrue(options.allSatisfy { !$0.artworkFilename.isEmpty && $0.artworkFilename.hasSuffix(".webp") })
        XCTAssertEqual(BG3BuildArtwork.slug(for: "Hunter's Mark"), "hunter-s-mark")
        XCTAssertEqual(BG3BuildArtwork.slug(for: "Magic Initiate: Warlock"), "magic-initiate-warlock")
    }

    func testEveryCatalogChoiceHasBundledArtwork() {
        let options = BG3ClassCatalog.definitions.flatMap { definition in
            definition.levels.values.flatMap { level in
                level.features + level.choices.flatMap(\.options)
            }
        }
        let iconDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "BG3Assistant/Resources/BuildOptionIcons", directoryHint: .isDirectory)
        let missing = Set(options.map(\.artworkFilename)).filter {
            !FileManager.default.fileExists(atPath: iconDirectory.appending(path: $0).path)
        }

        XCTAssertTrue(missing.isEmpty, "Missing build artwork: \(missing.sorted().joined(separator: ", "))")
    }

    func testLegacyRunsReceiveBalancedDifficultyAndFullRoute() {
        var run = HonorRun()
        run.difficulty = nil
        run.routeRevealPolicy = nil
        run.normalizeRoster()

        XCTAssertEqual(run.difficulty, .balanced)
        XCTAssertEqual(run.routeRevealPolicy, .everything)
    }
}
