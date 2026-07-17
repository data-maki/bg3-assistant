from fastapi.testclient import TestClient

from app.main import app
from app.route_data import item_key, load_gear


client = TestClient(app)


def test_act_catalog_uses_separate_equipment_databases():
    response = client.get("/api/acts")
    assert response.status_code == 200
    acts = response.json()
    assert [entry["equipmentFile"] for entry in acts] == [
        "gear/act1.tsv",
        "gear/act2.tsv",
        "gear/act3.tsv",
    ]
    # Counts are distinct catalog items per act (the same item listed for
    # several builds is one row), not raw TSV rows.
    expected = [
        len({item_key(item.item) for item in load_gear(act)})
        for act in (1, 2, 3)
    ]
    assert [entry["equipmentCount"] for entry in acts] == expected
    assert acts[0]["routeAvailable"] is True
    assert acts[1]["routeAvailable"] is False


def test_act_two_equipment_is_isolated_and_coordinate_backed():
    act_two = load_gear(2)
    assert act_two
    assert {item.act for item in act_two} == {2}
    assert all(item.game_x is not None and item.game_y is not None for item in act_two if item.map_objective)
    helmet = next(item for item in act_two if item.item == "Helmet of Arcane Acuity")
    assert (helmet.game_x, helmet.game_y) == (107, -758)

    response = client.get("/api/acts/2/map")
    assert response.status_code == 200
    payload = response.json()
    assert payload["mapName"] == "Shadow-Cursed Lands"
    assert payload["mapUrl"].endswith("/shadow-cursed-lands")
    assert len(payload["equipment"]) == len({item_key(item.item) for item in act_two if item.map_objective})


def test_unknown_act_is_not_exposed():
    assert client.get("/api/acts/4/equipment").status_code == 404
    assert client.get("/api/acts/4/map").status_code == 404
