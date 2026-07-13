"""Tests for the unified markers payload and the shared run-state endpoint."""

from fastapi.testclient import TestClient

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
                "equipped": ["titanstring-bow", "gloves-of-archery", "titanstring-bow"],
                "equippedByMember": {
                    "tav": ["titanstring-bow", "titanstring-bow"],
                    "companion-1": ["gloves-of-archery"],
                },
                "builds": ["b1", "b2", "b1"],
                "done": ["fight-owlbear", "fight-owlbear"],
                "party": [
                    {"id": "tav", "name": "Tav", "level": 4, "buildId": "b1"},
                    {"id": "companion-1", "name": "Shadowheart", "level": 3, "buildId": "b2"},
                ],
            },
        )
        assert response.status_code == 200
        state = response.json()
        assert state["ok"]
        assert state["equipped"] == ["gloves-of-archery", "titanstring-bow"]  # deduped, sorted
        assert state["equippedByMember"]["tav"] == ["titanstring-bow"]
        assert state["builds"] == ["b1", "b2"]  # deduped, order preserved
        assert state["done"] == ["fight-owlbear"]
        assert state["party"][1] == {"id": "companion-1", "name": "Shadowheart", "level": 3, "buildId": "b2"}

        fetched = client.get("/api/run-state").json()
        assert fetched["equipped"] == state["equipped"]
        assert fetched["equippedByMember"] == state["equippedByMember"]
        assert fetched["done"] == state["done"]
        assert fetched["party"] == state["party"]
