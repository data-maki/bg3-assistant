import XCTest
@testable import BG3HonorAssistant

final class RunCreationTests: XCTestCase {
    private let latestScores = AbilityScores(
        strength: 8, dexterity: 16, constitution: 14,
        intelligence: 10, wisdom: 10, charisma: 17
    )

    private func latestBuild() -> BuildSummary {
        BuildSummary(
            id: "latest-build",
            name: "Latest Swords Bard",
            honorStatus: "Reviewed",
            role: "Control",
            finalSplit: "Bard 12",
            classProgression: "Bard 1-12",
            startingAbilities: "",
            startingAbilityScores: latestScores,
            playPattern: "",
            caveat: "",
            source: "",
            levels: [
                BuildLevel(
                    level: 1, take: "Bard 1", subclassChoice: "-",
                    choices: "", tactics: "", confidence: "Reviewed"
                )
            ],
            gear: []
        )
    }

    func testFreshRunKeepsCharacterAndLatestBuildPresetsOnly() throws {
        var source = HonorRun()
        source.normalizeRoster()
        source.name = "Old Run"
        source.guideVersion = "old-guide"
        source.selectedAct = 3
        source.storyOutcomes = ["saved-grove"]
        source.walkthroughProgress = ["step": .completed]
        source.walkthroughOutcomes = ["step": "choice"]
        source.equippedByMember = ["tav": ["old-item"]]
        source.equipmentOwnershipKnown = true
        source.gearAssignmentOverrides = ["old-item": "tav"]
        source.plannedSlotOverrides = ["tav": ["main-hand": "old-item"]]
        source.gearTarget = GearTarget(memberId: "tav", buildId: "latest-build", gearId: "old-item")
        source.mapRegion = "Lower City"

        let tavIndex = try XCTUnwrap(source.roster?.firstIndex { $0.id == "tav" })
        source.roster?[tavIndex].name = "Ariadne"
        source.roster?[tavIndex].level = 12
        source.roster?[tavIndex].buildId = "latest-build"
        source.roster?[tavIndex].className = "Old class"
        source.roster?[tavIndex].abilityScores = .customDefault
        source.roster?[tavIndex].abilityModifiers = [
            AbilityModifier(
                ability: .strength, kind: .permanent, mode: .add,
                value: 1, source: "Old reward"
            )
        ]
        source.roster?[tavIndex].appliedAbilitySetupId = "old-setup"

        let shadowheartIndex = try XCTUnwrap(source.roster?.firstIndex { $0.name == "Shadowheart" })
        source.roster?[shadowheartIndex].buildId = "removed-build"
        source.roster?[shadowheartIndex].status = .dead
        source.syncActivePartyProjection()

        let createdAt = Date(timeIntervalSince1970: 1234)
        let fresh = source.freshRun(
            name: "New Run",
            guideVersion: "latest-guide",
            availableBuilds: [latestBuild()],
            createdAt: createdAt
        )

        XCTAssertNotEqual(fresh.id, source.id)
        XCTAssertEqual(fresh.name, "New Run")
        XCTAssertEqual(fresh.createdAt, createdAt)
        XCTAssertEqual(fresh.guideVersion, "latest-guide")
        XCTAssertEqual(fresh.selectedAct, 1)
        XCTAssertTrue(fresh.progress.isEmpty)
        XCTAssertTrue(fresh.walkthroughProgress.isEmpty ?? true)
        XCTAssertTrue(fresh.walkthroughOutcomes.isEmpty ?? true)
        XCTAssertTrue(fresh.storyOutcomes.isEmpty ?? true)
        XCTAssertTrue(fresh.equippedByMember.isEmpty ?? true)
        XCTAssertFalse(fresh.equipmentOwnershipKnown ?? true)
        XCTAssertTrue(fresh.gearAssignmentOverrides.isEmpty ?? true)
        XCTAssertTrue(fresh.plannedSlotOverrides.isEmpty)
        XCTAssertNil(fresh.gearTarget)
        XCTAssertEqual(fresh.mapRegion, "Wilderness")

        let tav = try XCTUnwrap(fresh.roster?.first { $0.id == "tav" })
        XCTAssertEqual(tav.name, "Ariadne")
        XCTAssertEqual(tav.level, 1)
        XCTAssertEqual(tav.buildId, "latest-build")
        XCTAssertEqual(tav.className, "Bard 1")
        XCTAssertEqual(tav.abilityScores, latestScores)
        XCTAssertTrue(tav.abilityModifiers?.isEmpty ?? false)
        XCTAssertNil(tav.appliedAbilitySetupId)

        let shadowheart = try XCTUnwrap(fresh.roster?.first { $0.name == "Shadowheart" })
        XCTAssertNil(shadowheart.buildId)
        XCTAssertEqual(shadowheart.rosterStatus, .active)
    }
}
