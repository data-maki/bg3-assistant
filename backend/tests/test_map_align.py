"""Tests for the in-game map alignment engine.

The synthetic-zoom tests reproduce the Mac app's screenshot → align → overlay
loop: they render fake "game screenshots" of the map at several zoom levels
(with HUD chrome noise), run the registration, and assert the recovered
transform places known targets within a few pixels of ground truth.
"""

import math

import cv2
import numpy as np
import pytest
from conftest import BLIGHTED_VILLAGE, GOBLIN_CAMP, synthetic_screenshot

from app.map_align import MOSAIC_SIZE, get_aligner
from app.mercator import latlng_to_mosaic_px, mosaic_px_to_latlng


class TestMercator:
    def test_roundtrip(self) -> None:
        for lat, lng in [BLIGHTED_VILLAGE, GOBLIN_CAMP, (0.7, -1.0), (0.6, -0.4)]:
            x, y = latlng_to_mosaic_px(lat, lng)
            back_lat, back_lng = mosaic_px_to_latlng(x, y)
            assert math.isclose(back_lat, lat, abs_tol=1e-9)
            assert math.isclose(back_lng, lng, abs_tol=1e-9)

    def test_known_anchors_land_inside_mosaic(self) -> None:
        for lat, lng in [BLIGHTED_VILLAGE, GOBLIN_CAMP]:
            x, y = latlng_to_mosaic_px(lat, lng)
            assert 0 <= x <= MOSAIC_SIZE
            assert 0 <= y <= MOSAIC_SIZE


@pytest.fixture(scope="module")
def aligner():
    instance = get_aligner()
    if instance is None:
        pytest.skip("mosaic tile cache unavailable")
    return instance


class TestAlignZoomLoop:
    @pytest.mark.parametrize("zoom", [0.55, 1.0, 2.0, 3.5])
    def test_alignment_recovers_view_across_zoom_levels(self, aligner, zoom: float) -> None:
        center = latlng_to_mosaic_px(*BLIGHTED_VILLAGE)
        image, (x0, y0, z) = synthetic_screenshot(aligner.mosaic, center, zoom)

        result = aligner.align(image)
        assert result is not None, f"alignment failed entirely at zoom {zoom}"
        assert result.map_open, f"map not recognised at zoom {zoom} (inliers={result.inliers})"

        # Recovered zoom scale should match the synthetic zoom closely.
        assert result.scale == pytest.approx(z, rel=0.06)

        # Project a known target and compare against ground truth screen px.
        target_mosaic = latlng_to_mosaic_px(*GOBLIN_CAMP)
        expected = ((target_mosaic[0] - x0) * z, (target_mosaic[1] - y0) * z)
        got = result.latlng_to_screen(*GOBLIN_CAMP)
        error = math.hypot(got[0] - expected[0], got[1] - expected[1])
        assert error < 9, f"target projection off by {error:.1f}px at zoom {zoom}"

    def test_view_center_maps_to_player_position_estimate(self, aligner) -> None:
        center = latlng_to_mosaic_px(*GOBLIN_CAMP)
        image, (x0, y0, z) = synthetic_screenshot(aligner.mosaic, center, 1.4)
        result = aligner.align(image)
        assert result is not None and result.map_open
        lat, lng = result.center_latlng
        cx, cy = latlng_to_mosaic_px(lat, lng)
        expected_cx, expected_cy = x0 + 800 / z, y0 + 450 / z
        assert math.hypot(cx - expected_cx, cy - expected_cy) < 8

    def test_non_map_screenshot_is_rejected(self, aligner) -> None:
        rng = np.random.default_rng(7)
        noise = rng.integers(0, 255, size=(900, 1600), dtype=np.uint8)
        ok, buf = cv2.imencode(".jpg", noise)
        assert ok
        result = aligner.align(buf.tobytes())
        assert result is None or not result.map_open
