from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_act_one_map_page_loads() -> None:
    response = client.get("/map")
    assert response.status_code == 200
    assert "Act 1 Honor walkthrough" in response.text
    assert "Open MapGenie Wilderness" in response.text


def test_root_serves_the_map_and_assets_never_go_stale() -> None:
    response = client.get("/", follow_redirects=True)
    assert response.status_code == 200
    assert "Act 1 Honor walkthrough" in response.text
    assert response.headers["cache-control"] == "no-cache"
    asset = client.get("/map-assets/app.js")
    assert asset.status_code == 200
    assert asset.headers["cache-control"] == "no-cache"


def test_walkthrough_detail_is_action_first_with_one_depth_control() -> None:
    script = client.get("/map-assets/js/walkthrough.js")
    assert script.status_code == 200
    assert 'const instructionLabel = step.decision ? "SAY" : "DO"' in script.text
    assert '<summary>More context</summary>' in script.text
    assert '<summary>Other outcome</summary>' in script.text
    assert "Decision tradeoff" not in script.text
    assert "Panic plan + Honor delta" not in script.text
    assert "Why do this or skip it?" not in script.text
    assert "Party stabilized" not in script.text
    assert "postFightItems" not in script.text
    assert "ENCOUNTER-SPECIFIC AFTERMATH" in script.text


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

    assert len(markers) == 72
    assert len({marker["id"] for marker in markers}) == 72
    assert sum(marker["type"] == "fight" for marker in markers) == 19
    assert sum(marker["type"] == "item" for marker in markers) == 53
    assert all(marker["region"] != "Other Act 1" for marker in markers)
    assert payload["mapgenieUrl"] == "https://mapgenie.io/baldurs-gate-3/maps/wilderness"


# Bounding boxes (lat_min, lat_max, lng_min, lng_max) of each region's landmass
# on the MapGenie Wilderness mosaic. Interior cells (Zhentarim Hideout, the
# grove interior, sanctum, …) float as their own islands, so a marker whose
# pin is outside its region's box is on the WRONG landmass — that is exactly
# the "Underdark showing up under Wilderness" bug.
REGION_LANDMASS_BOUNDS = {
    "Wilderness": (0.56, 0.79, -0.68, -0.43),
    "Underdark": (0.62, 0.80, -0.95, -0.77),
    "Whispering Depths": (0.61, 0.68, -0.81, -0.71),
    "Grymforge": (0.63, 0.79, -1.06, -0.94),
    "Overgrown Tunnel": (0.56, 0.63, -0.74, -0.64),
    "Owlbear Nest": (0.78, 0.83, -0.60, -0.55),
    "Shattered Sanctum": (0.71, 0.79, -0.80, -0.69),
    "Emerald Grove": (0.71, 0.80, -0.48, -0.32),
    "Zhentarim Hideout": (0.79, 0.86, -0.67, -0.61),
    "Apothecary's Cellar": (0.60, 0.66, -0.72, -0.66),
    "Mountain Pass": (0.70, 0.75, -0.66, -0.62),
    "Crèche Y'llek": (0.70, 0.75, -0.66, -0.62),
    "Nautiloid": (0.56, 0.61, -0.51, -0.46),
}


def test_every_marker_sits_on_its_regions_landmass() -> None:
    payload = client.get("/api/act1/markers").json()
    misplaced = []
    for marker in payload["markers"]:
        bounds = REGION_LANDMASS_BOUNDS.get(marker["region"])
        assert bounds is not None, f"no landmass bounds defined for region {marker['region']!r}"
        lat_min, lat_max, lng_min, lng_max = bounds
        if not (lat_min <= marker["lat"] <= lat_max and lng_min <= marker["lng"] <= lng_max):
            misplaced.append(f"{marker['name']} ({marker['region']}) at {marker['lat']:.3f},{marker['lng']:.3f}")
    assert not misplaced, "markers on the wrong landmass: " + "; ".join(misplaced)


def test_wilderness_region_never_reaches_underground_landmasses() -> None:
    payload = client.get("/api/act1/markers").json()
    wilderness = [m for m in payload["markers"] if m["region"] == "Wilderness"]
    assert wilderness
    # Fitting the view to Wilderness markers must keep the frame on the
    # surface: nothing west of the Whispering Depths edge, nothing on the
    # interior islands north-east of the Zhentarim cell.
    assert all(m["lng"] > -0.70 for m in wilderness)
    assert all(m["lat"] < 0.79 for m in wilderness)


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


def test_flamadin_and_control_martial_have_complete_act_one_interim_loadouts() -> None:
    payload = client.get("/api/act1/markers").json()
    builds = {build["id"]: build for build in payload["builds"]}
    required_slots = {"Head", "Chest", "Hands", "Feet", "Amulet", "Ring", "Ranged"}

    for build_id in ("PA-FL", "SB-1011"):
        gear = [item for item in builds[build_id]["gear"] if item["act"] == 1]
        slots = {item["slot"] for item in gear}
        assert required_slots <= slots, f"{build_id} missing Act 1 interim slots: {required_slots - slots}"
        assert all(item["acquisition"] and item["region"] and item["source"].startswith("http") for item in gear)

    flamadin_items = {item["item"] for item in builds["PA-FL"]["gear"] if item["act"] == 1}
    control_items = {item["item"] for item in builds["SB-1011"]["gear"] if item["act"] == 1}
    assert {"Flame Blade", "Haste Helm", "Adamantine Scale Mail", "Amulet of Misty Step"} <= flamadin_items
    assert {"Hand Crossbow +1 x2", "The Shadespell Circlet", "Pearl of Power Amulet", "Gloves of Dexterity"} <= control_items


def test_open_hand_monk_has_a_compatible_disposition_at_every_act_one_level() -> None:
    payload = client.get("/api/act1/markers").json()
    monk = next(build for build in payload["builds"] if build["id"] == "MO-OH")
    required_slots = {"Head", "Chest", "Hands", "Feet", "Amulet", "Ring", "Melee", "Off-hand", "Ranged", "Cloak"}

    for level in range(1, 8):
        current = [
            item for item in monk["gear"]
            if item["act"] == 1
            and item["minimumLevel"] <= level
            and (item["maximumLevel"] is None or level <= item["maximumLevel"])
        ]
        slots = {item["slot"] for item in current}
        assert required_slots <= slots, f"Monk L{level} missing slot disposition: {required_slots - slots}"
        assert all(item["acquisition"] and item["source"].startswith("http") for item in current)

    splint = next(item for item in monk["gear"] if item["item"] == "Adamantine Splint Armour")
    assert splint["minimumLevel"] == 8
    assert "Fighter" in splint["requirement"] and "heavy-armour" in splint["requirement"]
    assert all(item["alternative"] for item in monk["gear"] if item["mapObjective"] and item["act"] == 1)

    marker_names = {marker["name"] for marker in payload["markers"] if marker["type"] == "item"}
    assert {
        "Haste Helm", "Swiresy Shoes", "The Sparkle Hands", "The Graceful Cloth",
        "Sentient Amulet", "Crusher's Ring", "Ring of Protection", "Bow of Awareness",
    } <= marker_names


def test_warlock_eldritch_knight_has_full_progression_and_act_one_bridge() -> None:
    payload = client.get("/api/act1/markers").json()
    build = next(build for build in payload["builds"] if build["id"] == "FI-WEK")
    assert len(build["levels"]) == 12
    assert build["levels"][4]["take"] == "Warlock 5"
    assert build["levels"][5]["take"] == "Respec: Fighter 6"
    assert build["levels"][-1]["take"] == "Warlock 4"
    assert {item["act"] for item in build["gear"]} == {1, 2, 3}
    assert {
        "Phalar Aluve", "Warped Headband of Intellect", "Boots of Stormy Clamour",
        "Gloves of Belligerent Skies", "Ring of Arcane Synergy", "Psychic Spark",
    } <= {item["item"] for item in build["gear"] if item["act"] == 1}
