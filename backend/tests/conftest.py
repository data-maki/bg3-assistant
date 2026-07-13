"""Shared helpers: synthetic in-game map screenshots for alignment tests."""

import atexit
import os
import tempfile

import cv2
import numpy as np


# API tests mutate run progress by design. Keep that state out of both the
# developer map and the packaged app's Application Support run.
_test_state = tempfile.TemporaryDirectory(prefix="bg3-assistant-tests-")
atexit.register(_test_state.cleanup)
os.environ["RUNS_DIR"] = _test_state.name

BLIGHTED_VILLAGE = (0.66787, -0.58407)  # known MapGenie anchor on the surface
GOBLIN_CAMP = (0.68803, -0.62842)


def synthetic_screenshot(mosaic, center_xy, zoom, size=(1600, 900)):
    """Render a fake in-game map screenshot.

    zoom = screenshot pixels per mosaic pixel. Returns (jpeg bytes,
    (crop_x0, crop_y0, zoom)) so ground-truth screen positions can be computed
    as (mosaic_px - crop_origin) * zoom.
    """
    from app.map_align import MOSAIC_SIZE

    width, height = size
    crop_w, crop_h = width / zoom, height / zoom
    x0 = min(max(0.0, center_xy[0] - crop_w / 2), MOSAIC_SIZE - crop_w)
    y0 = min(max(0.0, center_xy[1] - crop_h / 2), MOSAIC_SIZE - crop_h)
    crop = mosaic[int(y0) : int(y0 + crop_h), int(x0) : int(x0 + crop_w)]
    frame = cv2.resize(crop, (width, height), interpolation=cv2.INTER_LINEAR)
    # HUD chrome noise: dark bars + fake button text, like the real map screen.
    frame[:56, :] = 12
    frame[-72:, :] = 8
    cv2.putText(frame, "Waypoints  Show Party  Place Marker", (40, 36), cv2.FONT_HERSHEY_SIMPLEX, 0.9, 235, 2)
    cv2.putText(frame, "Journal  Camp  Legend", (40, height - 28), cv2.FONT_HERSHEY_SIMPLEX, 0.9, 235, 2)
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 86])
    assert ok
    return buf.tobytes(), (int(x0), int(y0), zoom)
