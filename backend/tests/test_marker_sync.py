from fastapi.testclient import TestClient
from uuid import uuid4

from app.main import app


client = TestClient(app)


def preview(**overrides):
    payload = {
        "act": 1,
        "partyLevel": 3,
        "buildIds": ["CL-102", "MO-OH"],
        "completedCheckpointIds": ["fight-nautiloid-zhalk"],
        "equippedItemKeys": [],
        **overrides,
    }
    response = client.post("/api/marker-sync/preview", json=payload)
    assert response.status_code == 200
    return response.json()


def test_preview_is_level_build_and_region_aware() -> None:
    payload = preview()
    assert payload["act"] == 1
    assert payload["partyLevel"] == 3
    assert payload["phase"] == "Wilderness"
    assert payload["markers"]
    assert all(marker["recommendedLevel"] <= 3 for marker in payload["markers"])
    assert all(marker["region"] not in {"Underdark", "Grymforge", "Mountain Pass", "Crèche Y'llek"} for marker in payload["markers"])
    assert any(marker["type"] == "fight" for marker in payload["markers"])
    assert any(marker["type"] == "item" for marker in payload["markers"])
    assert all(len(marker["label"]) <= 36 and marker["label"].startswith("L") for marker in payload["markers"])
    assert len({marker["label"] for marker in payload["markers"]}) == len(payload["markers"])
    assert {marker["levelSource"] for marker in payload["markers"]} == {"guide_fact", "assistant_suggestion"}


def test_preview_omits_completed_and_equipped_markers() -> None:
    initial = preview()
    fight = next(marker for marker in initial["markers"] if marker["type"] == "fight")
    item = next(marker for marker in initial["markers"] if marker["type"] == "item")
    # Use the canonical item key from the map payload rather than deriving it
    # from display text/area punctuation.
    map_payload = client.get("/api/act1/markers").json()
    canonical_item_key = next(marker["itemKey"] for marker in map_payload["markers"] if marker["id"] == item["id"])
    changed = preview(
        completedCheckpointIds=["fight-nautiloid-zhalk", fight["id"]],
        equippedItemKeys=[canonical_item_key],
    )
    ids = {marker["id"] for marker in changed["markers"]}
    assert fight["id"] not in ids
    assert item["id"] not in ids
    assert changed["fingerprint"] != initial["fingerprint"]


def test_unreviewed_act_returns_an_explicit_blocker() -> None:
    payload = preview(act=2)
    assert payload["markers"] == []
    assert payload["warnings"] == ["Act 2 marker coordinates have not been reviewed yet."]


def test_confirmed_fingerprint_is_not_silently_repeated() -> None:
    unique_done = f"test-only-{uuid4()}"
    first = preview(completedCheckpointIds=["fight-nautiloid-zhalk", unique_done])
    assert first["alreadySynced"] is False
    response = client.post("/api/marker-sync/confirm", json={"fingerprint": first["fingerprint"]})
    assert response.status_code == 200
    repeated = preview(completedCheckpointIds=["fight-nautiloid-zhalk", unique_done])
    assert repeated["fingerprint"] == first["fingerprint"]
    assert repeated["alreadySynced"] is True
