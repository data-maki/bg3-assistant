"""Web Mercator math for the MapGenie Wilderness tileset.

MapGenie renders its BG3 maps in standard Web Mercator (EPSG:3857) in a tiny
patch near the null island, so MapGenie latitude/longitude values convert to
tile pixels with the ordinary slippy-map formulas. The alignment mosaic is the
16x16 tile block at zoom 12 that contains the whole Wilderness map.
"""

import math

MOSAIC_ZOOM = 12
TILE_SIZE = 256
TILE_ORIGIN = 2032  # first tile index (both axes) of the Wilderness tileset at z12
MOSAIC_TILES = 16
MOSAIC_SIZE = TILE_SIZE * MOSAIC_TILES

_WORLD_PX = TILE_SIZE * (2**MOSAIC_ZOOM)
_ORIGIN_PX = TILE_ORIGIN * TILE_SIZE


def latlng_to_mosaic_px(lat: float, lng: float) -> tuple[float, float]:
    x = (lng + 180.0) / 360.0 * _WORLD_PX - _ORIGIN_PX
    lat_rad = math.radians(lat)
    y = (1.0 - math.log(math.tan(math.pi / 4.0 + lat_rad / 2.0)) / math.pi) / 2.0 * _WORLD_PX - _ORIGIN_PX
    return x, y


def mosaic_px_to_latlng(x: float, y: float) -> tuple[float, float]:
    lng = (x + _ORIGIN_PX) / _WORLD_PX * 360.0 - 180.0
    n = math.pi * (1.0 - 2.0 * (y + _ORIGIN_PX) / _WORLD_PX)
    lat = math.degrees(math.atan(math.sinh(n)))
    return lat, lng
