"""Register in-game map screenshots against the MapGenie Wilderness mosaic.

The in-game map and MapGenie's tiles are the same artwork, so ORB keypoint
matching plus a RANSAC similarity fit recovers the game map's pan/zoom
deterministically and locally (no LLM call). The inlier count doubles as a
robust "the map screen is actually open" signal: arbitrary gameplay frames
produce no geometrically consistent match.
"""

from __future__ import annotations

import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from .config import get_settings
from .mercator import (
    MOSAIC_SIZE,
    MOSAIC_TILES,
    TILE_ORIGIN,
    TILE_SIZE,
    latlng_to_mosaic_px,
    mosaic_px_to_latlng,
)

__all__ = ["MOSAIC_SIZE", "AlignResult", "MapAligner", "get_aligner"]

TILE_URL = "https://tiles.mapgenie.io/games/baldurs-gate-3/wilderness/default-v4/12/{x}/{y}.jpg"

MIN_INLIERS = 20
STRONG_INLIERS = 60
MAX_INPUT_DIM = 1600
# The game map can be zoomed far past the mosaic's native resolution; probing
# the screenshot at several downscales keeps ORB within its scale tolerance.
PROBE_SCALES = (1.0, 0.6, 0.35, 0.2, 0.125)


@dataclass
class AlignResult:
    map_open: bool
    inliers: int
    confidence: float
    image_size: tuple[int, int]  # (width, height) of the submitted screenshot
    screen_to_mosaic: np.ndarray  # 2x3 affine
    mosaic_to_screen: np.ndarray  # 2x3 affine

    @property
    def scale(self) -> float:
        """Screenshot pixels per mosaic pixel (the game map's zoom)."""
        a, b = self.mosaic_to_screen[0, 0], self.mosaic_to_screen[0, 1]
        return float(np.hypot(a, b))

    @property
    def center_latlng(self) -> tuple[float, float]:
        cx, cy = self.screen_to_latlng(self.image_size[0] / 2.0, self.image_size[1] / 2.0)
        return cx, cy

    def latlng_to_screen(self, lat: float, lng: float) -> tuple[float, float]:
        mx, my = latlng_to_mosaic_px(lat, lng)
        m = self.mosaic_to_screen
        return (
            float(m[0, 0] * mx + m[0, 1] * my + m[0, 2]),
            float(m[1, 0] * mx + m[1, 1] * my + m[1, 2]),
        )

    def screen_to_latlng(self, x: float, y: float) -> tuple[float, float]:
        m = self.screen_to_mosaic
        mx = m[0, 0] * x + m[0, 1] * y + m[0, 2]
        my = m[1, 0] * x + m[1, 1] * y + m[1, 2]
        return mosaic_px_to_latlng(float(mx), float(my))


class MapAligner:
    def __init__(self, mosaic: np.ndarray) -> None:
        self.mosaic = mosaic
        self._query_orb = cv2.ORB_create(nfeatures=4000, fastThreshold=12)
        index_orb = cv2.ORB_create(nfeatures=60000, fastThreshold=12)
        self._index_kp, self._index_des = index_orb.detectAndCompute(mosaic, None)
        self._matcher = cv2.BFMatcher(cv2.NORM_HAMMING)

    def align(self, image_bytes: bytes) -> AlignResult | None:
        raw = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(raw, cv2.IMREAD_GRAYSCALE)
        if image is None or self._index_des is None or len(self._index_des) < 100:
            return None
        full_h, full_w = image.shape[:2]

        pre_scale = min(1.0, MAX_INPUT_DIM / max(full_w, full_h))
        if pre_scale < 1.0:
            image = cv2.resize(image, None, fx=pre_scale, fy=pre_scale, interpolation=cv2.INTER_AREA)

        best: tuple[int, np.ndarray, float] | None = None  # (inliers, matrix, total_scale)
        for probe in PROBE_SCALES:
            probed = image if probe == 1.0 else cv2.resize(image, None, fx=probe, fy=probe, interpolation=cv2.INTER_AREA)
            if min(probed.shape[:2]) < 180:
                continue
            keypoints, descriptors = self._query_orb.detectAndCompute(probed, None)
            if descriptors is None or len(descriptors) < 40:
                continue
            pairs = self._matcher.knnMatch(descriptors, self._index_des, k=2)
            good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < 0.8 * n.distance]
            if len(good) < 15:
                continue
            src = np.float32([keypoints[m.queryIdx].pt for m in good])
            dst = np.float32([self._index_kp[m.trainIdx].pt for m in good])
            matrix, mask = cv2.estimateAffinePartial2D(
                src, dst, method=cv2.RANSAC, ransacReprojThreshold=4.0, maxIters=4000, confidence=0.995
            )
            if matrix is None or mask is None:
                continue
            inliers = int(mask.sum())
            if best is None or inliers > best[0]:
                best = (inliers, matrix, pre_scale * probe)
            if inliers >= STRONG_INLIERS:
                break

        if best is None:
            return None
        inliers, matrix, total_scale = best

        # `matrix` maps probed-screenshot px -> mosaic px. Fold the probe/input
        # downscale in so the transform applies to full-resolution screenshots.
        screen_to_mosaic = matrix.copy()
        screen_to_mosaic[:, :2] *= total_scale
        mosaic_to_screen = cv2.invertAffineTransform(screen_to_mosaic)

        return AlignResult(
            map_open=inliers >= MIN_INLIERS,
            inliers=inliers,
            confidence=min(1.0, inliers / 100.0),
            image_size=(full_w, full_h),
            screen_to_mosaic=screen_to_mosaic,
            mosaic_to_screen=mosaic_to_screen,
        )


def _cache_dir() -> Path:
    return get_settings().runs_dir / "map_cache" / "z12"


def _ensure_tiles(cache: Path) -> int:
    """Download any missing mosaic tiles; returns the number available."""
    cache.mkdir(parents=True, exist_ok=True)

    def fetch(tile: tuple[int, int]) -> bool:
        tx, ty = tile
        path = cache / f"{tx}_{ty}.jpg"
        if path.exists() and path.stat().st_size > 0:
            return True
        path.unlink(missing_ok=True)
        request = urllib.request.Request(
            TILE_URL.format(x=tx, y=ty),
            headers={"User-Agent": "Mozilla/5.0", "Referer": "https://mapgenie.io/"},
        )
        try:
            with urllib.request.urlopen(request, timeout=4) as response:
                data = response.read()
            if data:
                path.write_bytes(data)
                return True
        except Exception:
            pass
        return False

    tiles = [
        (tx, ty)
        for tx in range(TILE_ORIGIN, TILE_ORIGIN + MOSAIC_TILES)
        for ty in range(TILE_ORIGIN, TILE_ORIGIN + MOSAIC_TILES)
    ]
    with ThreadPoolExecutor(max_workers=12, thread_name_prefix="map-tile") as pool:
        return sum(pool.map(fetch, tiles))


def _load_mosaic(cache: Path) -> np.ndarray | None:
    mosaic = np.zeros((MOSAIC_SIZE, MOSAIC_SIZE), dtype=np.uint8)
    loaded = 0
    for tx in range(TILE_ORIGIN, TILE_ORIGIN + MOSAIC_TILES):
        for ty in range(TILE_ORIGIN, TILE_ORIGIN + MOSAIC_TILES):
            path = cache / f"{tx}_{ty}.jpg"
            if not path.exists() or path.stat().st_size == 0:
                continue
            tile = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
            if tile is None:
                continue
            col, row = tx - TILE_ORIGIN, ty - TILE_ORIGIN
            mosaic[row * TILE_SIZE : (row + 1) * TILE_SIZE, col * TILE_SIZE : (col + 1) * TILE_SIZE] = tile
            loaded += 1
    return mosaic if loaded >= 32 else None


_aligner: MapAligner | None = None
_aligner_failed = False
_lock = threading.Lock()


def get_aligner() -> MapAligner | None:
    """Lazy singleton; builds the ORB index once (~1-2s) on first use."""
    global _aligner, _aligner_failed
    with _lock:
        if _aligner is not None or _aligner_failed:
            return _aligner
        cache = _cache_dir()
        try:
            _ensure_tiles(cache)
        except Exception:
            pass
        mosaic = _load_mosaic(cache)
        if mosaic is None:
            _aligner_failed = True
            return None
        _aligner = MapAligner(mosaic)
        return _aligner
