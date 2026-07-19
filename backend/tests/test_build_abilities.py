from app.route_data import load_builds


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
