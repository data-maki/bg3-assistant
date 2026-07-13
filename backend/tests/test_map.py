from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_act_one_map_page_loads() -> None:
    response = client.get("/map")
    assert response.status_code == 200
    assert "Act 1 route map" in response.text
    assert "Open MapGenie Wilderness" in response.text


def test_root_serves_the_map_and_assets_never_go_stale() -> None:
    response = client.get("/", follow_redirects=True)
    assert response.status_code == 200
    assert "Act 1 route map" in response.text
    assert response.headers["cache-control"] == "no-cache"
    asset = client.get("/map-assets/app.js")
    assert asset.status_code == 200
    assert asset.headers["cache-control"] == "no-cache"


def test_stars_cleric_build_is_respec_free_and_cleric_through_act_one() -> None:
    payload = client.get("/api/act1/markers").json()
    build = next(b for b in payload["builds"] if b["id"] == "CL-102")
    by_level = {row["level"]: row["take"] for row in build["levels"]}
    assert all(by_level[level].startswith("Cleric") for level in range(1, 6)), "Act 1 must be pure Cleric"
    assert by_level[6].startswith("Druid") and by_level[7].startswith("Druid")
    assert all(by_level[level].startswith("Cleric") for level in range(8, 13))
    assert not any("respec" in row["take"].lower() for row in build["levels"])


def test_act_one_marker_inventory_is_complete() -> None:
    response = client.get("/api/act1/markers")
    assert response.status_code == 200
    payload = response.json()
    markers = payload["markers"]

    assert len(markers) == 56
    assert len({marker["id"] for marker in markers}) == 56
    assert sum(marker["type"] == "fight" for marker in markers) == 19
    assert sum(marker["type"] == "item" for marker in markers) == 37
    assert all(marker["region"] != "Other Act 1" for marker in markers)
    assert payload["mapgenieUrl"] == "https://mapgenie.io/baldurs-gate-3/maps/wilderness"


def test_every_build_has_act_one_items() -> None:
    payload = client.get("/api/act1/markers").json()
    item_build_ids = {
        build_id
        for marker in payload["markers"]
        if marker["type"] == "item"
        for build_id in marker["buildIds"]
    }
    expected_build_ids = {build["id"] for build in payload["builds"]}
    assert expected_build_ids <= item_build_ids
    assert {"PA-FL", "WI-BS"} <= expected_build_ids
    assert not {"PA-WL", "PK-SB"} & expected_build_ids
