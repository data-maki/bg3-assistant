"""End-to-end tests for the screenshot → position → overlay loop endpoints."""

import json
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.map_align import get_aligner
from app.mercator import latlng_to_mosaic_px

from conftest import BLIGHTED_VILLAGE, synthetic_screenshot

client = TestClient(app)


@pytest.fixture(scope="module")
def map_screenshot() -> bytes:
    aligner = get_aligner()
    if aligner is None:
        pytest.skip("mosaic tile cache unavailable")
    center = latlng_to_mosaic_px(*BLIGHTED_VILLAGE)
    image, _ = synthetic_screenshot(aligner.mosaic, center, zoom=1.5)
    return image


def test_position_roundtrip() -> None:
    response = client.post("/api/position", json={"lat": 0.68, "lng": -0.58, "source": "manual"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] and payload["position"]["source"] == "manual"

    response = client.get("/api/position")
    position = response.json()["position"]
    assert position["lat"] == 0.68 and position["lng"] == -0.58
    assert position["updated_at"] > 0


def test_map_align_full_loop(map_screenshot: bytes) -> None:
    context = json.dumps({"checkpoint_id": "fight-blighted-village", "completed_checkpoint_ids": []})
    response = client.post(
        "/api/map-align",
        files={"image": ("map.jpg", map_screenshot, "image/jpeg")},
        data={"context": context},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] and payload["map_open"]
    assert payload["inliers"] >= 20
    assert payload["zoom"] == pytest.approx(1.5, rel=0.08)

    # The view is centred on Blighted Village, so that target must be near the
    # centre of the 1600x900 synthetic screenshot and flagged on-screen.
    targets = {target["id"]: target for target in payload["targets"]}
    assert "fight-blighted-village" in targets
    blighted = targets["fight-blighted-village"]
    assert blighted["on_screen"]
    assert abs(blighted["x"] - 800) < 25 and abs(blighted["y"] - 450) < 25

    # A successful alignment publishes the live position estimate.
    position = client.get("/api/position").json()["position"]
    assert position["source"] == "map-align"
    assert position["lat"] == pytest.approx(BLIGHTED_VILLAGE[0], abs=0.002)
    assert position["lng"] == pytest.approx(BLIGHTED_VILLAGE[1], abs=0.002)


def test_map_align_projects_requested_export_markers(map_screenshot: bytes) -> None:
    context = json.dumps(
        {
            "marker_ids": ["fight-blighted-village", "item-the-sparkle-hands-sunlit-wetlands"],
            "marker_labels": {"fight-blighted-village": "L3 Fight Blighted Village"},
        }
    )
    response = client.post(
        "/api/map-align",
        files={"image": ("map.jpg", map_screenshot, "image/jpeg")},
        data={"context": context},
    )
    assert response.status_code == 200
    targets = {target["id"]: target for target in response.json()["targets"]}
    assert set(targets) == {"fight-blighted-village", "item-the-sparkle-hands-sunlit-wetlands"}
    assert targets["fight-blighted-village"]["label"] == "L3 Fight Blighted Village"
    assert targets["fight-blighted-village"]["kind"] == "fight"
    assert targets["item-the-sparkle-hands-sunlit-wetlands"]["kind"] == "item"


def test_map_align_projects_the_active_export_queue(map_screenshot: bytes) -> None:
    preview = client.post(
        "/api/marker-sync/preview",
        json={
            "act": 1,
            "partyLevel": 3,
            "buildIds": ["CL-102"],
            "completedCheckpointIds": ["fight-nautiloid-zhalk"],
            "equippedItemKeys": [],
        },
    ).json()
    response = client.post(
        "/api/map-align",
        files={"image": ("map.jpg", map_screenshot, "image/jpeg")},
        data={"context": json.dumps({"use_active_marker_sync": True})},
    )
    targets = response.json()["targets"]
    assert [target["id"] for target in targets] == [marker["id"] for marker in preview["markers"]]
    assert [target["label"] for target in targets] == [marker["label"] for marker in preview["markers"]]


def test_confirmed_export_queue_stops_the_temporary_overlay(map_screenshot: bytes) -> None:
    preview = client.post(
        "/api/marker-sync/preview",
        json={
            "act": 1,
            "partyLevel": 3,
            "buildIds": ["CL-102"],
            "completedCheckpointIds": ["fight-nautiloid-zhalk", f"test-only-{uuid4()}"],
            "equippedItemKeys": [],
        },
    ).json()
    assert client.post("/api/marker-sync/confirm", json={"fingerprint": preview["fingerprint"]}).status_code == 200
    response = client.post(
        "/api/map-align",
        files={"image": ("map.jpg", map_screenshot, "image/jpeg")},
        data={"context": json.dumps({"use_active_marker_sync": True})},
    )
    assert response.json()["targets"] == []


def test_map_align_rejects_gameplay_frame() -> None:
    import cv2
    import numpy as np

    rng = np.random.default_rng(11)
    frame = rng.integers(0, 255, size=(720, 1280, 3), dtype=np.uint8)
    ok, buffer = cv2.imencode(".jpg", frame)
    assert ok
    response = client.post("/api/map-align", files={"image": ("shot.jpg", buffer.tobytes(), "image/jpeg")})
    payload = response.json()
    assert payload["ok"] is True
    assert payload["map_open"] is False
    assert payload["targets"] == []
