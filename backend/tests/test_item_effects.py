"""Coverage tests for the wiki-sourced item effects join."""

from app.map_data import load_act_one_map
from app.route_data import load_builds


class TestItemEffects:
    def test_items_carry_effects_and_acquisition(self) -> None:
        payload = load_act_one_map()
        items = [m for m in payload.markers if m.type == "item"]
        with_effect = [m for m in items if m.effect]
        with_acquire = [m for m in items if m.acquire_detail]
        # bg3.wiki coverage: every item should say what it does; nearly every
        # one should say where it comes from (summoned spells have no place).
        assert len(with_effect) == len(items)
        assert len(with_acquire) >= len(items) - 2
        assert all(m.wiki and m.wiki.startswith("https://bg3.wiki/wiki/") for m in with_effect)

    def test_effects_join_reaches_builds_payload(self) -> None:
        builds = load_builds()
        act_one_gear = [g for b in builds for g in b.gear if g.act == 1 and g.map_objective]
        assert act_one_gear
        assert sum(1 for g in act_one_gear if g.effect) == len(act_one_gear)
