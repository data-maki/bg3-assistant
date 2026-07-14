"""Companion web-map payload: markers, builds, and timed events.

All guide facts come from route_data's typed loaders (the single parse of the
data files). This module owns only what the map uniquely needs: MapGenie
coordinates for every marker, region naming for item locations, and the
assembled payload.

MapGenie renders its BG3 maps in standard Web Mercator (Mapbox GL), so
Leaflet's default CRS aligns 1:1 and markers can be placed directly with
MapGenie's own latitude/longitude values, reverse-engineered from its public
map data (https://mapgenie.io/api/v1/maps/123/data) and matched to our curated
markers by name.
"""

import json
import logging
import re

from .models import ActOneMap, BuildGear, Marker, MapTiles, RouteCheckpoint, TimedEvent
from .paths import resource_root
from .route_data import checkpoint_by_id, item_key, load_gear, load_builds, load_route, next_checkpoint
from .walkthrough_data import load_walkthrough

logger = logging.getLogger(__name__)

REPO_ROOT = resource_root()
TIMED_EVENTS_PATH = REPO_ROOT / "data" / "act1_timed_events.json"

MAP_TILES = MapTiles(
    tile_url="https://tiles.mapgenie.io/games/baldurs-gate-3/wilderness/default-v4/{z}/{x}/{y}.jpg",
    min_zoom=8,
    max_zoom=16,
    start={"lat": 0.6868, "lng": -0.5795, "zoom": 12},
    attribution="Base map © MapGenie",
)

_MG_START = (MAP_TILES.start.lat, MAP_TILES.start.lng)

# Which named submap an item location belongs to. Order matters: more specific
# phrases must precede broader ones.
REGION_BY_PHRASE = [
    ("Crèche Y'llek", "Crèche Y'llek"),
    ("Rosymorn Monastery", "Mountain Pass"),
    ("Selûnite Outpost", "Underdark"),
    ("Myconid Colony", "Underdark"),
    ("Adamantine Forge", "Grymforge"),
    ("Grymforge", "Grymforge"),
    ("Shattered Sanctum", "Shattered Sanctum"),
    ("Blighted Village", "Wilderness"),
    ("Druid Grove", "Wilderness"),
    ("Goblin Camp", "Wilderness"),
    ("Zhentarim Hideout", "Zhentarim Hideout"),
    ("Waukeen's Rest", "Wilderness"),
    ("The Risen Road", "Wilderness"),
    ("Sunlit Wetlands", "Wilderness"),
    ("Apothecary's Cellar", "Apothecary's Cellar"),
    ("Nautiloid helm", "Nautiloid"),
    ("Underdark", "Underdark"),
]

# Locations naming two acquisition spots produce one marker per spot.
AREA_SPLITS = {
    "Druid Grove / Shattered Sanctum": [("Druid Grove", "Wilderness"), ("Shattered Sanctum", "Shattered Sanctum")],
    "Druid Grove / Goblin Camp": [("Druid Grove", "Wilderness"), ("Goblin Camp", "Wilderness")],
}

# Items whose MapGenie pin sits on an interior cell (its own landmass on the
# mosaic) even though the curated location names the parent area. The region
# must match the landmass the pin is on — otherwise selecting "Wilderness"
# fits the view across the whole canvas and drags the Underdark into frame.
ITEM_REGION_OVERRIDES = {
    "Ring of Protection": "Emerald Grove",
    "Broodmother's Revenge": "Emerald Grove",
    "Hellrider's Pride": "Emerald Grove",
}

# Coarse area anchors (lat, lng) on the Wilderness tileset. Used for markers
# whose exact spot is not individually mapped — the Crèche/Rosymorn zone is
# reached through the Mountain Pass, Nautiloid content anchors to the arrival
# beach. Order matters: more specific phrases first.
MG_AREA_ANCHORS: list[tuple[str, tuple[float, float]]] = [
    ("Crèche Y'llek", (0.72467, -0.64191)),
    ("Rosymorn Monastery", (0.72467, -0.64191)),
    ("Mountain Pass", (0.72467, -0.64191)),
    ("Nautiloid", (0.58761, -0.48547)),
    ("Ravaged Beach", (0.58761, -0.48547)),
    ("Selûnite Outpost", (0.69993, -0.81571)),
    ("Myconid Colony", (0.75763, -0.84832)),
    ("Adamantine Forge", (0.66378, -0.97569)),
    ("Grymforge", (0.72893, -1.01707)),
    ("Shattered Sanctum", (0.75900, -0.76600)),
    ("Druid Grove", (0.68895, -0.50750)),
    ("Goblin Camp", (0.68803, -0.62842)),
    ("Zhentarim Hideout", (0.80748, -0.65037)),
    ("Waukeen's Rest", (0.74011, -0.63212)),
    ("The Risen Road tollhouse", (0.72146, -0.54213)),
    ("Risen Road", (0.75298, -0.56147)),
    ("Riverside Teahouse", (0.60452, -0.60194)),
    ("Sunlit Wetlands", (0.60807, -0.59043)),
    ("Blighted Village", (0.66787, -0.58407)),
    ("Whispering Depths", (0.64596, -0.79235)),
    ("Owlbear Nest", (0.80821, -0.57349)),
    ("Overgrown Tunnel", (0.58611, -0.71830)),
    ("Apothecary's Cellar", (0.62820, -0.68940)),
    ("Underdark", (0.71600, -0.85000)),
]

# Exact MapGenie coordinates for each Act 1 fight, keyed by fight id.
# "area" precision marks encounters not on the Wilderness tileset (Nautiloid,
# Crèche) that anchor coarsely to their access point.
MG_FIGHT_COORDS: dict[str, tuple[float, float, str]] = {
    "fight-nautiloid-zhalk": (0.58761, -0.48547, "area"),
    "fight-grove-entrance": (0.67759, -0.49484, "exact"),
    "fight-harpies": (0.73674, -0.46633, "exact"),
    "fight-spider-matriarch": (0.66054, -0.77626, "exact"),
    "fight-owlbear": (0.80821, -0.57349, "exact"),
    "fight-blighted-village": (0.66787, -0.58407, "exact"),
    "fight-goblin-leaders": (0.75900, -0.76600, "exact"),
    "fight-redcaps": (0.61145, -0.59078, "exact"),
    "fight-wood-woads": (0.59221, -0.56252, "exact"),
    "fight-auntie-ethel": (0.58611, -0.71830, "exact"),
    "fight-gnolls": (0.72980, -0.60070, "exact"),
    "fight-underdark-minotaurs": (0.73853, -0.82410, "exact"),
    "fight-spectator": (0.69350, -0.84102, "exact"),
    "fight-arcane-tower": (0.67933, -0.89709, "exact"),
    "fight-sussur-hook-horrors": (0.74550, -0.90900, "exact"),
    "fight-nere": (0.69760, -1.01044, "exact"),
    "fight-grym": (0.66323, -0.97747, "exact"),
    "fight-gith-patrol": (0.73821, -0.65740, "exact"),
    "fight-wargaz": (0.72467, -0.64191, "area"),
}

# Exact MapGenie coordinates for individually-mapped items, keyed by item name
# as it appears in the gear TSV — or "item|area" when a dual-location item has
# an exact pin for only one of its markers (the other falls back to its area
# anchor instead of borrowing the wrong landmass's coordinate).
MG_ITEM_COORDS: dict[str, tuple[float, float]] = {
    "Haste Helm": (0.67051, -0.58509),
    "Crusher's Ring": (0.66777, -0.64225),
    "Breastplate +1": (0.73725, -0.52151),
    "Safeguard Shield": (0.73787, -0.52188),
    "Gloves of Archery": (0.68160, -0.63960),
    "Gloves of the Growling Underdog": (0.76947, -0.76564),
    "Boots of Striding": (0.75925, -0.74873),
    "Amulet of Misty Step": (0.74325, -0.72735),
    "Titanstring Bow": (0.82260, -0.63260),
    "Phalar Aluve": (0.71870, -0.84270),
    "Svartlebee's Woundseeker": (0.75740, -0.62530),
    "Sword of Justice": (0.73960, -0.55120),
    "Luminous Armour": (0.69550, -0.81670),
    "The Whispering Promise|Goblin Camp": (0.68080, -0.63950),
    "Hellrider's Pride": (0.78350, -0.45720),
    "The Sparkle Hands": (0.58790, -0.55730),
    "Disintegrating Night Walkers": (0.69810, -1.01100),
    "Adamantine Scale Mail": (0.66072, -0.97707),
    "Adamantine Splint Armour": (0.66070, -0.97780),
    "Bracers of Defence": (0.62820, -0.68940),
    "Ring of Protection": (0.78720, -0.40000),
    "Broodmother's Revenge": (0.73150, -0.35700),
    "Bow of Awareness": (0.72890, -0.77680),
    "The Spellsparkler": (0.75590, -0.62410),
    "Melf's First Staff": (0.76040, -0.84440),
    "Pearl of Power Amulet": (0.76352, -0.84472),
    "The Shadespell Circlet": (0.76352, -0.84472),
    "Caustic Band": (0.75966, -0.87043),
    "The Protecty Sparkswall": (0.71980, -1.01580),
}


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")




def _mg_anchor(*locations: str) -> tuple[float, float] | None:
    for location in locations:
        for phrase, latlng in MG_AREA_ANCHORS:
            if location and phrase.lower() in location.lower():
                return latlng
    return None


def _region_for(location: str) -> str:
    for phrase, region in REGION_BY_PHRASE:
        if phrase.lower() in location.lower():
            return region
    return "Other Act 1"


def _item_areas(location: str) -> list[tuple[str, str]]:
    return AREA_SPLITS.get(location) or [(location, _region_for(location))]


def _place(name: str, *anchor_hints: str) -> tuple[float, float, str]:
    """Resolve (lat, lng, precision) for a marker, loudly flagging data gaps."""
    anchor = _mg_anchor(*anchor_hints)
    if anchor is None:
        logger.warning("No MapGenie anchor matches %r (hints %r); marker is unanchored", name, anchor_hints)
        return (*_MG_START, "unanchored")
    return (*anchor, "area")


def _fight_markers() -> list[Marker]:
    markers = []
    for checkpoint in load_route():
        exact = MG_FIGHT_COORDS.get(checkpoint.id)
        lat, lng, precision = exact if exact else _place(checkpoint.name, checkpoint.region, checkpoint.area)
        markers.append(
            Marker(
                id=checkpoint.id,
                name=checkpoint.name,
                type="fight",
                area=checkpoint.area,
                region=checkpoint.region,
                lat=lat,
                lng=lng,
                precision=precision,
                advice=checkpoint.advice,
                source=checkpoint.source.url,
                importance=checkpoint.importance,
                minimum_level=checkpoint.minimum_level,
                danger=checkpoint.danger,
                route_order=checkpoint.route_order,
                enemies=checkpoint.enemies,
                legendary_action=checkpoint.legendary_action,
                failure_conditions=checkpoint.failure_conditions,
                preparation=checkpoint.preparation,
                irreversible_warnings=checkpoint.irreversible_warnings,
            )
        )
    return markers


def _item_markers() -> list[Marker]:
    markers: dict[tuple[str, str], Marker] = {}
    for gear in (item for item in load_gear() if item.act == 1 and item.map_objective):
        for area, region in _item_areas(gear.region):
            key = (gear.item, area)
            if existing := markers.get(key):
                existing.build_ids = sorted(set(existing.build_ids) | set(gear.build_ids))
                continue
            region = ITEM_REGION_OVERRIDES.get(gear.item, region)
            exact = MG_ITEM_COORDS.get(f"{gear.item}|{area}") or MG_ITEM_COORDS.get(gear.item)
            lat, lng, precision = (*exact, "exact") if exact else _place(gear.item, area, gear.region, region)
            markers[key] = Marker(
                id=f"item-{_slug(gear.item)}-{_slug(area)}",
                name=gear.item,
                type="item",
                area=area,
                region=region,
                lat=lat,
                lng=lng,
                precision=precision,
                advice=gear.acquisition,
                source=gear.source,
                importance="item",
                build_ids=sorted(gear.build_ids),
                item_key=item_key(gear.item),
                icon=gear.icon or None,
                slot=gear.slot,
                priority=gear.priority,
                why=gear.why,
                effect=gear.effect or None,
                acquire_detail=gear.acquire or None,
                wiki=gear.wiki or None,
            )
    return list(markers.values())


def _timed_events() -> list[TimedEvent]:
    try:
        return [TimedEvent(**event) for event in json.loads(TIMED_EVENTS_PATH.read_text(encoding="utf-8"))]
    except Exception:
        logger.warning("Timed events data unavailable", exc_info=True)
        return []


def load_act_one_map() -> ActOneMap:
    markers = _fight_markers() + _item_markers()
    return ActOneMap(
        act=1,
        markers=markers,
        regions=sorted({marker.region for marker in markers}),
        builds=load_builds(),
        timed_events=_timed_events(),
        walkthrough=load_walkthrough(),
        mapgenie_url="https://mapgenie.io/baldurs-gate-3/maps/wilderness",
        mapgenie=MAP_TILES,
        coordinate_note=(
            "Pins are aligned to MapGenie's official Wilderness map. Exact pins sit on the "
            "matched location; area pins mark the correct named area (e.g. Crèche gear via the "
            "Mountain Pass) without claiming false precision."
        ),
    )


def overlay_targets(checkpoint_id: str | None, completed: set[str]) -> list[tuple[RouteCheckpoint, float, float]]:
    """The next few uncompleted checkpoints with their MapGenie coordinates,
    for projection onto the in-game map overlay."""
    current = None
    if checkpoint_id:
        try:
            current = checkpoint_by_id(checkpoint_id)
        except KeyError:
            current = None
    if current is None:
        current = next_checkpoint(completed)
    min_order = current.route_order if current else 0
    upcoming = [
        checkpoint
        for checkpoint in load_route()
        if checkpoint.id not in completed and checkpoint.route_order >= min_order
    ][:6]
    targets = []
    for checkpoint in upcoming:
        exact = MG_FIGHT_COORDS.get(checkpoint.id)
        lat, lng, _ = exact if exact else _place(checkpoint.name, checkpoint.region, checkpoint.area)
        targets.append((checkpoint, lat, lng))
    return targets
