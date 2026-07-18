from app.route_data import load_builds
from fastapi.testclient import TestClient

from app import main


def test_reviewed_builds_expose_starting_and_target_abilities():
    builds = load_builds()
    assert all(build.starting_ability_scores is not None for build in builds)
    assert all(build.target_ability_scores is not None for build in builds)
    smite_bard = next(build for build in builds if build.id == "SB-102")
    assert smite_bard.starting_ability_scores.strength == 17
    assert smite_bard.target_ability_scores.strength == 22
    assert smite_bard.target_ability_note
    assert smite_bard.ability_setups[-1].id == "respec-l7"
    assert smite_bard.ability_setups[-1].point_buy_scores.dexterity == 8
    assert smite_bard.ability_setups[-1].final_scores.wisdom == 10
    assert any(source.item_key == "gloves-of-dexterity" for source in smite_bard.ability_sources)


def test_control_martial_records_level_eight_respec_scores():
    build = next(build for build in load_builds() if build.id == "SB-1011")
    respec = next(level for level in build.levels if level.level == 8)
    assert respec.ability_score_reset.dexterity == 8
    assert respec.ability_score_reset.intelligence == 16


def test_every_reviewed_setup_is_a_valid_exact_bg3_recipe():
    costs = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
    abilities = ("strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma")
    for build in load_builds():
        assert build.ability_setups, build.id
        for setup in build.ability_setups:
            assert setup.bonus_two != setup.bonus_one
            assert sum(costs[getattr(setup.point_buy_scores, ability)] for ability in abilities) == 27
            for ability in abilities:
                expected = getattr(setup.point_buy_scores, ability)
                expected += 2 if ability == setup.bonus_two else 1 if ability == setup.bonus_one else 0
                assert getattr(setup.final_scores, ability) == expected


def test_ability_plan_uses_native_and_browser_key_aliases():
    build = next(build for build in load_builds() if build.id == "MO-OH")
    native = build.model_dump()
    browser = build.model_dump(by_alias=True)
    assert native["ability_setups"][0]["point_buy_scores"]["dexterity"] == 15
    assert browser["abilitySetups"][0]["pointBuyScores"]["dexterity"] == 15
    assert browser["abilitySources"][0]["itemKey"] == "elixir-of-hill-giant-strength"


def test_native_and_map_endpoints_publish_ability_recipes():
    client = TestClient(main.app)
    native_build = next(build for build in client.get("/api/act1/route").json()["builds"] if build["id"] == "SB-1011")
    map_build = next(build for build in client.get("/api/act1/markers").json()["builds"] if build["id"] == "SB-1011")
    assert native_build["ability_setups"][1]["id"] == "respec-l8"
    assert native_build["target_ability_note"]
    assert map_build["abilitySetups"][1]["id"] == "respec-l8"
    assert map_build["abilitySources"][0]["itemKey"] == "gloves-of-dexterity"
