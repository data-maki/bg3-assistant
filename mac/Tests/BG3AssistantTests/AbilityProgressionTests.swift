import XCTest
@testable import BG3HonorAssistant

final class AbilityProgressionTests: XCTestCase {
    private let setup = AbilitySetupPlan(
        id: "creation",
        level: 1,
        label: "Character creation",
        reason: "Test setup",
        pointBuyScores: AbilityScores(
            strength: 10, dexterity: 15, constitution: 15,
            intelligence: 8, wisdom: 14, charisma: 8
        ),
        bonusTwo: .wisdom,
        bonusOne: .dexterity,
        finalScores: AbilityScores(
            strength: 10, dexterity: 16, constitution: 15,
            intelligence: 8, wisdom: 16, charisma: 8
        ),
        firstClass: "Monk",
        classOrder: "Monk 1-12"
    )

    private func build(sources: [AbilityPlanSource] = []) -> BuildSummary {
        BuildSummary(
            id: "test", name: "Test build", honorStatus: "Reviewed", role: "Test",
            finalSplit: "Monk 12", classProgression: "Monk", startingAbilities: "",
            startingAbilityScores: setup.finalScores,
            targetAbilityScores: AbilityScores(
                strength: 22, dexterity: 16, constitution: 15,
                intelligence: 8, wisdom: 16, charisma: 8
            ),
            targetAbilityNote: "Stable target",
            abilitySetups: [setup], abilitySources: sources,
            playPattern: "", caveat: "", source: "", levels: [], gear: []
        )
    }

    private func member(modifiers: [AbilityModifier] = []) -> PartyMember {
        PartyMember(
            id: "tav", name: "Tav", level: 12, buildId: "test", preparedTags: [],
            className: "Monk", status: .active, roleOverride: nil, isCustom: true,
            abilityScores: setup.finalScores, isHireling: false, sourceLoadoutId: nil,
            abilityModifiers: modifiers, usesBuildAbilityScores: true,
            appliedAbilitySetupId: "creation"
        )
    }

    func testStructuredSourcesKeepBuildTargetStableWhenCurrentExceedsIt() {
        let sources = [
            AbilityPlanSource(
                id: "asi", ability: .strength, kind: .asi, mode: .add, value: 2,
                label: "ASI", minimumLevel: 4
            ),
            AbilityPlanSource(
                id: "gear", ability: .strength, kind: .equipment, mode: .minimum, value: 23,
                label: "Gauntlets", itemKey: "gauntlets"
            ),
        ]
        let modifiers = [
            AbilityModifier(
                ability: .strength, kind: .permanent, mode: .add, value: 1,
                source: "Permanent", planSourceId: "permanent"
            ),
            AbilityModifier(
                ability: .strength, kind: .temporary, mode: .minimum, value: 27,
                source: "Cloud Giant", planSourceId: "cloud"
            ),
        ]
        let result = AbilityProgression.breakdown(
            for: member(modifiers: modifiers),
            build: build(sources: sources),
            ability: .strength,
            equippedItemKeys: ["gauntlets"]
        )
        XCTAssertEqual(result.starting, 10)
        XCTAssertEqual(result.levelGain, 2)
        XCTAssertEqual(result.current, 27)
        XCTAssertEqual(result.target, 22)
    }

}
