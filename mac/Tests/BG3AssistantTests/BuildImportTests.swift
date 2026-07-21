import XCTest
@testable import BG3HonorAssistant

final class BuildImportTests: XCTestCase {
    func testDraftProducesExplicitLegalStartingSetup() throws {
        let draft = makeDraft(finalSplit: "Monk 6 / Rogue 4 / Fighter 1 / Cleric 1")
        let imported = try draft.importedBuild(sourceURL: URL(string: "https://example.com/build")!)
        let setup = try XCTUnwrap(imported.build.abilitySetups?.first)

        XCTAssertTrue(AbilityProgression.isValidBG3Setup(setup))
        XCTAssertEqual(imported.build.startingAbilityScores?.dexterity, 16)
        XCTAssertEqual(imported.build.startingAbilityScores?.wisdom, 16)
    }

    func testDraftRejectsLevelTwelveClassSplitThatDoesNotTotalTwelve() {
        let draft = makeDraft(finalSplit: "Monk 8 / Rogue 4 / Fighter 1 / Cleric 1")

        XCTAssertThrowsError(try draft.importedBuild(sourceURL: URL(string: "https://example.com/build")!)) { error in
            XCTAssertTrue(error.localizedDescription.contains("totals 14, not 12"))
        }
    }

    func testDraftRepairsInvalidSplitFromCumulativeClassLevels() throws {
        let base = makeDraft(finalSplit: "Monk 8 / Cleric 1 / Rogue 4")
        let rows = [
            (1, "Monk 1"), (2, "Monk 2"), (3, "Monk 3"), (4, "Monk 4"),
            (5, "Monk 5"), (6, "Cleric 1"), (7, "Monk 6"), (8, "Fighter 1"),
            (9, "Rogue 1"), (10, "Rogue 3"), (11, "Rogue 3"), (12, "Rogue 4"),
        ].map { level, take in
            BuildImportLevel(
                level: level,
                take: take,
                subclassChoice: "",
                choices: "",
                tactics: "",
                confidence: "Explicit",
                abilityScoreReset: nil
            )
        }
        let draft = BuildImportDraft(
            name: base.name,
            role: base.role,
            finalSplit: base.finalSplit,
            classProgression: base.classProgression,
            pointBuyScores: base.pointBuyScores,
            bonusTwo: base.bonusTwo,
            bonusOne: base.bonusOne,
            playPattern: base.playPattern,
            caveat: base.caveat,
            levels: rows,
            gear: base.gear
        )

        let imported = try draft.importedBuild(sourceURL: URL(string: "https://example.com/build")!)

        XCTAssertEqual(imported.build.finalSplit, "Monk 6 / Cleric 1 / Fighter 1 / Rogue 4")
    }

    private func makeDraft(finalSplit: String) -> BuildImportDraft {
        BuildImportDraft(
            name: "Open Hand Monk",
            role: "Mobile striker",
            finalSplit: finalSplit,
            classProgression: "Monk, Rogue, Fighter, Cleric",
            pointBuyScores: AbilityScores(
                strength: 10,
                dexterity: 14,
                constitution: 15,
                intelligence: 8,
                wisdom: 15,
                charisma: 8
            ),
            bonusTwo: .dexterity,
            bonusOne: .wisdom,
            playPattern: "Use unarmed attacks and control.",
            caveat: "Requires a respec.",
            levels: [BuildImportLevel(
                level: 12,
                take: "Cleric 1",
                subclassChoice: "War Domain",
                choices: "",
                tactics: "",
                confidence: "Explicit",
                abilityScoreReset: nil
            )],
            gear: []
        )
    }
}
