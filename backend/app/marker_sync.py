"""Deterministic export queue for explicit BG3 custom-marker synchronization."""

import hashlib
import json
from collections import Counter

from .map_data import load_act_one_map
from .models import Marker, MarkerSyncMarker, MarkerSyncPreview, MarkerSyncRequest
from .route_data import next_checkpoint


PHASE_BY_REGION = {
    "Nautiloid": 0,
    "Underdark": 2,
    "Grymforge": 3,
    "Mountain Pass": 4,
    "Crèche Y'llek": 4,
}
PHASE_NAMES = {0: "Nautiloid", 1: "Wilderness", 2: "Underdark", 3: "Grymforge", 4: "Mountain Pass / Crèche"}
PRIORITY_ORDER = {"Required": 0, "Core": 1, "Upgrade": 2, "Starter": 3, "Support": 4, "Defence": 5, "Supply": 6, "Optional": 7}
MAX_BG3_LABEL = 36


def _phase(region: str) -> int:
    return PHASE_BY_REGION.get(region, 1)


def _label(level: int, marker: Marker, include_area: bool = False) -> str:
    kind = "Fight" if marker.type == "fight" else "Gear"
    prefix = f"L{level} {kind} "
    suffix = ""
    if include_area:
        area_room = 12
        area = marker.area if len(marker.area) <= area_room else marker.area[: area_room - 1].rstrip() + "…"
        suffix = f" @ {area}"
    room = max(1, MAX_BG3_LABEL - len(prefix) - len(suffix))
    name = marker.name if len(marker.name) <= room else marker.name[: max(1, room - 1)].rstrip() + "…"
    return prefix + name + suffix


def _fingerprint(request: MarkerSyncRequest, marker_ids: list[str]) -> str:
    canonical = {
        "act": request.act,
        "party_level": request.party_level,
        "build_ids": sorted(set(request.build_ids)),
        "completed": sorted(set(request.completed_checkpoint_ids)),
        "equipped": sorted(set(request.equipped_item_keys)),
        "markers": marker_ids,
    }
    return hashlib.sha256(json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:16]


def marker_sync_preview(request: MarkerSyncRequest) -> MarkerSyncPreview:
    if request.act != 1:
        return MarkerSyncPreview(
            act=request.act,
            party_level=request.party_level,
            phase=f"Act {request.act}",
            fingerprint=_fingerprint(request, []),
            warnings=[f"Act {request.act} marker coordinates have not been reviewed yet."],
        )

    completed = set(request.completed_checkpoint_ids)
    equipped = set(request.equipped_item_keys)
    build_ids = set(request.build_ids)
    recommended = next_checkpoint(completed=completed, party_level=request.party_level)
    current_phase = _phase(recommended.region) if recommended else 4
    map_markers = load_act_one_map().markers

    fights = [
        marker
        for marker in map_markers
        if marker.type == "fight"
        and marker.id not in completed
        and _phase(marker.region) == current_phase
        and (marker.minimum_level or 99) <= request.party_level
    ]
    fights.sort(key=lambda marker: (marker.route_order or 999, marker.name))

    items = [
        marker
        for marker in map_markers
        if marker.type == "item"
        and marker.item_key not in equipped
        and _phase(marker.region) == current_phase
        and build_ids.intersection(marker.build_ids)
    ]
    items.sort(key=lambda marker: (PRIORITY_ORDER.get(marker.priority or "", 99), marker.name, marker.area))
    item_name_counts = Counter(marker.name for marker in items)

    export: list[MarkerSyncMarker] = []
    for marker in [*fights, *items]:
        level = marker.minimum_level if marker.type == "fight" else request.party_level
        export.append(
            MarkerSyncMarker(
                id=marker.id,
                label=_label(
                    level or request.party_level,
                    marker,
                    include_area=marker.type == "item" and item_name_counts[marker.name] > 1,
                ),
                type=marker.type,
                region=marker.region,
                area=marker.area,
                lat=marker.lat,
                lng=marker.lng,
                precision=marker.precision,
                recommended_level=level or request.party_level,
                level_source="guide_fact" if marker.type == "fight" else "assistant_suggestion",
                reason=(
                    f"Incomplete {marker.importance} encounter at the guide minimum level."
                    if marker.type == "fight"
                    else f"{marker.priority} equipment for a selected build; not marked equipped."
                ),
                source=marker.source,
            )
        )

    warnings: list[str] = []
    if not build_ids:
        warnings.append("No reviewed party builds are selected, so equipment markers are omitted.")
    area_count = sum(marker.precision != "exact" for marker in export)
    if area_count:
        warnings.append(f"{area_count} marker(s) use reviewed area-level placement rather than an exact pin.")
    if not export:
        warnings.append("No unresolved fights or unequipped build items match this level and regional phase.")

    marker_ids = [marker.id for marker in export]
    return MarkerSyncPreview(
        act=1,
        party_level=request.party_level,
        phase=PHASE_NAMES[current_phase],
        fingerprint=_fingerprint(request, marker_ids),
        markers=export,
        warnings=warnings,
    )
