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
        source.selectedAct = 3
        source.storyOutcomes = ["saved-grove"]
        source.walkthroughProgress = ["step": .completed]
        source.equippedByMember = ["tav": ["old-item"]]
        source.gearTarget = GearTarget(memberId: "tav", buildId: "latest-build", gearId: "old-item")

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

        XCTAssertTrue(fresh.progress.isEmpty)
        XCTAssertTrue(fresh.walkthroughProgress?.isEmpty ?? true)
        XCTAssertTrue(fresh.storyOutcomes?.isEmpty ?? true)
        XCTAssertTrue(fresh.equippedByMember?.isEmpty ?? true)
        XCTAssertNil(fresh.gearTarget)

        let tav = try XCTUnwrap(fresh.roster?.first { $0.id == "tav" })
        XCTAssertEqual(tav.name, "Ariadne")
        XCTAssertEqual(tav.level, 1)
        XCTAssertEqual(tav.buildId, "latest-build")
        XCTAssertEqual(tav.className, "Bard 1")
        XCTAssertEqual(tav.abilityScores, latestScores)
        XCTAssertTrue(tav.abilityModifiers?.isEmpty ?? false)
        XCTAssertNil(tav.appliedAbilitySetupId)
        XCTAssertEqual(fresh.buildAssignedAt?[tav.id], createdAt)

        let shadowheart = try XCTUnwrap(fresh.roster?.first { $0.name == "Shadowheart" })
        XCTAssertNil(shadowheart.buildId)
        XCTAssertEqual(shadowheart.rosterStatus, .active)
    }
}
