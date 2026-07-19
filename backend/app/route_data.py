import csv
import json
import re
from functools import lru_cache
from pathlib import Path

from .models import AbilityScores, AbilityTargetScores, ActGuideSummary, BuildGear, BuildLevel, BuildSummary, ReadinessRequest, ReadinessResponse, RouteCheckpoint, TimedEvent
from .paths import resource_root


REPO_ROOT = resource_root()
BUILDS_PATH = REPO_ROOT / "data" / "build_overview.tsv"
BUILD_LEVELS_PATH = REPO_ROOT / "data" / "build_levels.tsv"
ACTS_PATH = REPO_ROOT / "data" / "acts"
ITEM_EFFECTS_PATH = REPO_ROOT / "data" / "item_effects.json"
ITEM_ICONS_PATH = REPO_ROOT / "data" / "item_icons.json"
BUILD_ABILITY_TARGETS_PATH = REPO_ROOT / "data" / "build_ability_targets.json"
SOURCE_URL = (
    "https://docs.google.com/spreadsheets/d/"
    "1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0"
)
GUIDE_VERSION = "2026-07-18-all-act-review-v2"


@lru_cache(maxsize=3)
def load_route(act: int = 1) -> list[RouteCheckpoint]:
    metadata = _act_metadata(act)
    if not metadata["routeAvailable"]:
        return []
    prefix = REPO_ROOT / "data" / f"act{act}"
    fights = {row["id"]: row for row in json.loads(prefix.with_name(f"act{act}_fights.json").read_text(encoding="utf-8"))}
    reviewed = json.loads(prefix.with_name(f"act{act}_route.json").read_text(encoding="utf-8"))
    decisions_path = prefix.with_name(f"act{act}_decisions.json")
    decisions = json.loads(decisions_path.read_text(encoding="utf-8")) if decisions_path.exists() else {}
    checkpoints: list[RouteCheckpoint] = []
    for route in reviewed:
        fight = fights[route["id"]]
        source = route.get("source") or {
            "sheet": "Act 1 - fights + Act 1 - Notes",
            "row": route["sourceRow"],
            "url": SOURCE_URL,
        }
        checkpoints.append(
            RouteCheckpoint(
                id=fight["id"],
                route_order=route["routeOrder"],
                name=fight["name"],
                area=fight["area"],
                region=fight["region"],
                x=fight["x"],
                y=fight["y"],
                minimum_level=fight["minimumLevel"],
                importance=fight["importance"],
                danger=route["danger"],
                enemies=fight["enemies"],
                advice=fight["advice"],
                legendary_action=route["legendaryAction"],
                failure_conditions=route["failureConditions"],
                preparation=route["preparation"],
                completion_checks=route["completionChecks"],
                irreversible_warnings=route["irreversibleWarnings"],
                prerequisites=route["prerequisites"],
                notes=route["notes"],
                honor_decisions=decisions.get(fight["id"], []),
                source=source,
            )
        )
    return sorted(checkpoints, key=lambda item: item.route_order)


@lru_cache(maxsize=3)
def load_timed_events(act: int = 1) -> list[TimedEvent]:
    metadata = _act_metadata(act)
    path = REPO_ROOT / "data" / f"act{act}_timed_events.json"
    if not metadata["routeAvailable"] or not path.exists():
        return []
    return [TimedEvent(**event) for event in json.loads(path.read_text(encoding="utf-8"))]


def item_key(item_name: str) -> str:
    """Stable per-item key (stack counts stripped) used for equip tracking
    and for joining gear rows with the wiki-sourced effects file."""
    stripped = re.sub(r"\s*x\d+$", "", item_name)
    return re.sub(r"[^a-z0-9]+", "-", stripped.lower()).strip("-")


def parse_ability_scores(value: str) -> AbilityScores | None:
    fields = {
        "STR": "strength",
        "DEX": "dexterity",
        "CON": "constitution",
        "INT": "intelligence",
        "WIS": "wisdom",
        "CHA": "charisma",
    }
    scores = {
        field: int(match.group(1))
        for key, field in fields.items()
        if (match := re.search(rf"\b{key}\s*(\d{{1,2}})\b", value, re.IGNORECASE))
    }
    if len(scores) != 6:
        return None
    return AbilityScores(**scores)


def _act_metadata(act: int) -> dict:
    if act not in (1, 2, 3):
        raise KeyError(act)
    return json.loads((ACTS_PATH / f"act{act}.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=4)
def load_gear(act: int | None = None) -> list[BuildGear]:
    """Reviewed gear rows from independent act-specific databases.

    Consumed per-build here (filtered into BuildSummary.gear), which seeds the
    relational catalog; item-wise serving (map markers, per-act equipment) now
    reads catalog.catalog_gear instead of this loader.
    Each row is joined with data/item_effects.json (built by
    backend/scripts/fetch_item_effects.py from bg3.wiki) for what the item does
    and exactly where it comes from.
    """
    acts = (act,) if act is not None else (1, 2, 3)
    rows = []
    for current_act in acts:
        metadata = _act_metadata(current_act)
        path = REPO_ROOT / "data" / metadata["equipmentFile"]
        with path.open(newline="", encoding="utf-8") as handle:
            rows.extend(csv.DictReader(handle, delimiter="\t"))
    try:
        effects = json.loads(ITEM_EFFECTS_PATH.read_text(encoding="utf-8"))
    except Exception:
        effects = {}
    try:
        icons = json.loads(ITEM_ICONS_PATH.read_text(encoding="utf-8"))
        icons_by_key = {item_key(name): f"/map-assets/{path}" for name, path in icons.items()}
    except Exception:
        icons_by_key = {}
    gear = []
    for row in rows:
        key = item_key(row["Item"])
        extra = effects.get(key, {})
        coordinate_match = re.fullmatch(r"X\s*(-?\d+)\s+Y\s*(-?\d+)", row.get("Coordinates") or "")
        minimum_level = int(row.get("Minimum level") or 1)
        maximum_level = int(row["Maximum level"]) if row.get("Maximum level") else None
        map_objective = (row.get("Map objective") or "yes").strip().lower() not in {"no", "false", "0"}
        gear.append(
            BuildGear(
                item=row["Item"],
                slot=row["Slot"],
                priority=row["Priority"],
                act=int(row["Act"]),
                region=row["Region / map"],
                acquisition=row["Location and acquisition"],
                why=row["Why / when"],
                source=row["Source"],
                build_ids=[value for value in row["Build IDs"].split(";") if value],
                minimum_level=minimum_level,
                maximum_level=maximum_level,
                requirement=row.get("Requirement") or "",
                map_objective=map_objective,
                alternative=row.get("Alternative") or "",
                effect=extra.get("effect", ""),
                acquire=extra.get("acquire", ""),
                wiki=extra.get("wiki", ""),
                icon=icons_by_key.get(key, ""),
                game_x=int(coordinate_match.group(1)) if coordinate_match else None,
                game_y=int(coordinate_match.group(2)) if coordinate_match else None,
            )
        )
    return gear


def load_act_catalog() -> list[ActGuideSummary]:
    # Uncached: equipment counts come from the catalog DB, which grows when
    # builds are imported. Function-local import avoids a module cycle
    # (catalog imports route_data for the TSV seed parsers).
    from . import catalog

    return [
        ActGuideSummary(**_act_metadata(act), equipment_count=len(catalog.catalog_gear(act)))
        for act in (1, 2, 3)
    ]


@lru_cache(maxsize=1)
def load_builds() -> list[BuildSummary]:
    with BUILDS_PATH.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    with BUILD_LEVELS_PATH.open(newline="", encoding="utf-8") as handle:
        level_rows = list(csv.DictReader(handle, delimiter="\t"))
    ability_targets = json.loads(BUILD_ABILITY_TARGETS_PATH.read_text(encoding="utf-8"))
    gear = load_gear()
    return [
        BuildSummary(
            id=row["Build ID"],
            name=row["Build / character plan"],
            honor_status=row["Honor status"],
            role=row["Role"],
            final_split=row["Final split"],
            class_progression=row["Class progression"],
            starting_abilities=row["Starting abilities"],
            starting_ability_scores=parse_ability_scores(row["Starting abilities"]),
            target_ability_scores=AbilityTargetScores(**ability_targets[row["Build ID"]]["scores"]),
            target_ability_note=ability_targets[row["Build ID"]].get("note", ""),
            ability_setups=ability_targets[row["Build ID"]].get("setups", []),
            ability_sources=ability_targets[row["Build ID"]].get("sources", []),
            play_pattern=row["Core play pattern"],
            caveat=row["Important caveat"],
            source=row["Primary source"],
            levels=[
                BuildLevel(
                    level=int(level["Character level"]),
                    take=level["Take"],
                    subclass_choice=level["Subclass / choice"],
                    choices=level["Feat / spells / skills"],
                    tactics=level["What changes now"],
                    confidence=level["Source confidence"],
                    ability_score_reset=parse_ability_scores(level["Feat / spells / skills"]),
                )
                for level in level_rows if level["Build ID"] == row["Build ID"]
            ],
            gear=[item for item in gear if row["Build ID"] in item.build_ids],
        )
        for row in rows
    ]


def checkpoint_by_id(checkpoint_id: str, act: int = 1) -> RouteCheckpoint:
    for checkpoint in load_route(act):
        if checkpoint.id == checkpoint_id:
            return checkpoint
    raise KeyError(checkpoint_id)


def assess_readiness(request: ReadinessRequest, act: int = 1) -> ReadinessResponse:
    checkpoint = checkpoint_by_id(request.checkpoint_id, act)
    active_party = [member for member in request.party if member.status in {None, "active"}]
    levels = [member.level for member in active_party]
    party_level = min(levels) if levels else 1
    completed = set(request.completed_checkpoint_ids)
    blockers: list[str] = []
    warnings: list[str] = []
    build_actions: list[str] = []

    if not active_party:
        blockers.append("No active party is recorded; confirm the active group before using readiness.")
    elif party_level < checkpoint.minimum_level:
        blockers.append(f"Lowest party member is level {party_level}; guide minimum is level {checkpoint.minimum_level}.")
    missing_prerequisites = [item for item in checkpoint.prerequisites if item not in completed]
    if missing_prerequisites:
        names = [checkpoint_by_id(item, act).name for item in missing_prerequisites]
        blockers.append("Unresolved reviewed route sequence: " + ", ".join(names))

    from .walkthrough_data import load_walkthrough, walkthrough_blockers

    steps = load_walkthrough(act)
    owning_step = next((step for step in steps if step.checkpoint_id == checkpoint.id), None)
    if owning_step:
        blockers.extend(
            walkthrough_blockers(
                owning_step,
                steps,
                request.walkthrough_statuses,
                request.walkthrough_outcomes,
            )
        )
    warnings.extend(checkpoint.irreversible_warnings)
    unchecked_preparation = [item for item in checkpoint.preparation if item not in request.checked_preparation]
    if unchecked_preparation:
        warnings.append("Preparation not confirmed: " + "; ".join(unchecked_preparation))

    from . import catalog

    builds = {build.id: build for build in catalog.catalog_builds()}
    assumed_build_setup: list[str] = []
    for member in active_party:
        if not member.build_id:
            continue
        build = builds.get(member.build_id)
        if build is None:
            warnings.append(f"{member.name} has an unknown build assignment ({member.build_id}).")
            continue
        level_plan = next((item for item in build.levels if item.level == member.level), None)
        reviewed_levels = [item for item in build.levels if item.level <= member.level]
        assumed_build_setup.extend(
            [
                build.role,
                build.play_pattern,
                build.class_progression,
                *(f"{item.take} {item.subclass_choice} {item.choices} {item.tactics}" for item in reviewed_levels),
            ]
        )
        if level_plan:
            build_actions.append(f"{member.name} L{member.level} ({build.name}): {level_plan.take}; {level_plan.tactics}")
        elif build.levels:
            warnings.append(f"{member.name}'s reviewed {build.name} plan ends at level {build.levels[-1].level}.")

    capability_terms = ["silence", "calm emotions", "sanctuary", "command", "bludgeoning", "fire", "counterspell", "initiative", "control"]
    requested_text = " ".join([checkpoint.advice, *checkpoint.preparation]).lower()
    recorded_capabilities = " ".join(
        [*(tag for member in active_party for tag in member.prepared_tags), *assumed_build_setup]
    ).lower()
    for capability in capability_terms:
        if capability in requested_text and capability not in recorded_capabilities:
            warnings.append(f"Party capability not recorded: {capability}. Confirm the party has it or choose an alternative plan.")

    if blockers:
        status = "blocked"
    elif checkpoint.danger == "extreme" or checkpoint.irreversible_warnings:
        status = "danger"
    elif checkpoint.danger == "high" or warnings:
        status = "caution"
    else:
        status = "ready"
    next_actions = blockers[:2] + unchecked_preparation[:2] + build_actions[:2]
    if not next_actions:
        next_actions = [checkpoint.advice]
    return ReadinessResponse(
        status=status,
        party_level=party_level,
        minimum_level=checkpoint.minimum_level,
        blockers=blockers,
        warnings=warnings,
        next_actions=next_actions,
    )
