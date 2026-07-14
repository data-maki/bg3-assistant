"""Tests for the unified markers payload and the shared run-state endpoint."""

from fastapi.testclient import TestClient

from app import stores
from app.config import get_settings
from app.main import app
from app.map_data import load_act_one_map

client = TestClient(app)


class TestMarkersPayload:
    def test_fights_carry_honor_intel(self) -> None:
        payload = load_act_one_map().model_dump(by_alias=True)
        fights = [m for m in payload["markers"] if m["type"] == "fight"]
        assert fights, "no fight markers"
        ethel = next(m for m in fights if m["id"] == "fight-auntie-ethel")
        assert ethel["legendaryAction"], "Ethel must carry her legendary action warning"
        assert ethel["failureConditions"], "Ethel must carry failure conditions"
        assert all(m["danger"] and m["routeOrder"] is not None for m in fights)

    def test_items_carry_icons_and_keys(self) -> None:
        payload = load_act_one_map().model_dump(by_alias=True)
        items = [m for m in payload["markers"] if m["type"] == "item"]
        assert items
        with_icon = [m for m in items if m.get("icon")]
        assert len(with_icon) >= len(items) * 0.9, "nearly all items should have icons"
        assert all(m["icon"].startswith("/map-assets/icons/") for m in with_icon), "icons must be servable URLs"
        assert all(m.get("itemKey") for m in items)
        # stack-count suffixes must not leak into keys
        torch = next(m for m in items if m["name"].startswith("Torch"))
        assert torch["itemKey"] == "torch"

    def test_no_marker_is_unanchored(self) -> None:
        payload = load_act_one_map()
        assert all(marker.precision in ("exact", "area") for marker in payload.markers), (
            "unanchored markers mean a location string no longer matches the anchor tables"
        )

    def test_one_build_vocabulary_across_payloads(self) -> None:
        """Web (camelCase) and Mac (snake_case) payloads come from one model."""
        web = client.get("/api/act1/markers").json()
        mac = client.get("/api/act1/route").json()
        web_level = web["builds"][0]["levels"][0]
        mac_level = mac["builds"][0]["levels"][0]
        assert {"subclassChoice", "choices", "tactics"} <= set(web_level)
        assert {"subclass_choice", "choices", "tactics"} <= set(mac_level)
        assert web_level["tactics"] == mac_level["tactics"]

    def test_builds_are_detailed(self) -> None:
        payload = client.get("/api/act1/markers").json()
        builds = payload["builds"]
        assert len(builds) >= 4
        first = builds[0]
        for field in ("role", "finalSplit", "classProgression", "playPattern", "levels"):
            assert field in first, f"build missing {field}"
        assert first["levels"], "builds should include the level-by-level plan"

    def test_timed_events_present(self) -> None:
        payload = client.get("/api/act1/markers").json()
        events = payload["timedEvents"]
        assert len(events) >= 10
        assert any(e["kind"] == "point_of_no_return" for e in events)
        assert all(e.get("consequence") and e.get("severity") for e in events)


class TestRunStateApi:
    def test_roundtrip_normalizes(self) -> None:
        response = client.post(
            "/api/run-state",
            json={
                "equippedByMember": {
                    "tav": ["titanstring-bow", "titanstring-bow"],
                    "companion-1": ["gloves-of-archery"],
                },
                "builds": ["b1", "b2", "b1"],
                "done": ["fight-owlbear", "fight-owlbear"],
                "focusedWalkthroughStepId": "walk-owlbear",
                "recoveryWalkthroughStepId": "retired-recovery-gate",
                "party": [
                    {"id": "tav", "name": "Tav", "level": 4, "buildId": "b1"},
                    {"id": "companion-1", "name": "Shadowheart", "level": 3, "buildId": "b2"},
                ],
            },
        )
        assert response.status_code == 200
        state = response.json()
        assert state["ok"]
        assert "equipped" not in state  # the flat legacy field is gone
        assert state["equippedByMember"] == {
            "tav": ["titanstring-bow"],  # deduped, sorted per member
            "companion-1": ["gloves-of-archery"],
        }
        assert state["builds"] == ["b1", "b2"]  # deduped, order preserved
        assert state["done"] == ["fight-owlbear"]
        assert state["focusedWalkthroughStepId"] == "walk-owlbear"
        assert "recoveryWalkthroughStepId" not in state
        assert state["party"][1]["id"] == "companion-1"
        assert state["party"][1]["name"] == "Shadowheart"
        assert state["party"][1]["level"] == 3
        assert state["party"][1]["buildId"] == "b2"
        assert state["party"][1]["status"] == "active"
        assert len(state["roster"]) == 7

        fetched = client.get("/api/run-state").json()
        assert fetched["equippedByMember"] == state["equippedByMember"]
        assert fetched["done"] == state["done"]
        assert fetched["focusedWalkthroughStepId"] == "walk-owlbear"
        assert fetched["party"] == state["party"]

    def test_full_roster_projects_at_most_four_active_members(self) -> None:
        roster = [
            {"id": f"m{index}", "name": name, "level": 4, "status": "active", "buildId": "MO-OH" if name == "Lae'zel" else None}
            for index, name in enumerate(["Tav", "Shadowheart", "Lae'zel", "Astarion", "Gale"])
        ]
        response = client.post(
            "/api/run-state",
            json={
                "roster": roster,
                "party": roster[:4],
                "storyOutcomes": ["karlach_killed_for_robe", "infernal_robe_obtained"],
                "includeCampPlans": True,
            },
        )
        assert response.status_code == 200
        state = response.json()
        assert len(state["party"]) == 4
        assert [member["status"] for member in state["roster"][:5]] == ["active", "active", "active", "active", "camp"]
        laezel = next(member for member in state["roster"] if member["name"] == "Lae'zel")
        assert laezel["buildId"] == "MO-OH"
        assert state["storyOutcomes"] == ["karlach_killed_for_robe", "infernal_robe_obtained"]
        assert state["includeCampPlans"] is True

    def test_dead_companion_is_not_in_active_projection(self) -> None:
        response = client.post(
            "/api/run-state",
            json={
                "roster": [
                    {"id": "tav", "name": "Tav", "level": 4, "status": "active"},
                    {"id": "karlach", "name": "Karlach", "level": 4, "status": "dead", "buildId": "MO-OH"},
                ]
            },
        )
        assert response.status_code == 200
        state = response.json()
        assert [member["name"] for member in state["party"]] == ["Tav"]
        karlach = next(member for member in state["roster"] if member["name"] == "Karlach")
        assert karlach["buildId"] == "MO-OH"

    def test_walkthrough_outcomes_roundtrip(self) -> None:
        # Decision steps record which option actually happened in this run.
        outcome = {"walk-rolan-stays": "Rolan punched Zevlor and the group left"}
        response = client.post("/api/run-state", json={"walkthroughOutcomes": outcome})
        assert response.status_code == 200
        assert response.json()["walkthroughOutcomes"] == outcome
        assert client.get("/api/run-state").json()["walkthroughOutcomes"] == outcome

    def test_native_snapshot_and_web_updates_share_one_sqlite_run(self) -> None:
        stores._run_database.save_snapshot({
            "id": "native-run",
            "guideVersion": "2026-07-12",
            "party": [
                {"id": "tav", "name": "Tav", "level": 5, "status": "active", "isCustom": True},
                {"id": "shadowheart", "name": "Shadowheart", "level": 5, "status": "active", "className": "Cleric"},
            ],
            "roster": [
                {"id": "tav", "name": "Tav", "level": 5, "status": "active", "isCustom": True},
                {"id": "shadowheart", "name": "Shadowheart", "level": 5, "status": "active", "className": "Cleric"},
            ],
            "progress": {},
            "walkthroughProgress": {
                "walk-nautiloid-zhalk": "completed",
                "walk-grove-entrance": "completed",
            },
            "walkthroughOutcomes": {},
            "mapRegion": "Wilderness",
            "selectedAct": 1,
        })

        state = client.get("/api/run-state").json()
        assert [member["level"] for member in state["party"]] == [5, 5]
        assert state["walkthroughStatuses"]["walk-nautiloid-zhalk"] == "done"
        assert "fight-nautiloid-zhalk" in state["done"]

        state["walkthroughStatuses"]["walk-harpies"] = "done"
        updated = client.post("/api/run-state", json=state)
        assert updated.status_code == 200
        snapshot = stores._run_database.load_snapshot()
        assert snapshot["id"] == "native-run"
        assert snapshot["walkthroughProgress"]["walk-harpies"] == "completed"
        assert snapshot["party"][0]["level"] == 5

        settings = get_settings()
        database_path = settings.state_database_path or settings.runs_dir / "state.sqlite3"
        assert database_path.exists()
