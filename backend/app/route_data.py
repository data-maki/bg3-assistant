import csv
import json
from functools import lru_cache
from pathlib import Path

from .models import BuildGear, BuildLevel, BuildSummary, ReadinessRequest, ReadinessResponse, RouteCheckpoint
from .paths import resource_root


REPO_ROOT = resource_root()
FIGHTS_PATH = REPO_ROOT / "data" / "act1_fights.json"
ROUTE_PATH = REPO_ROOT / "data" / "act1_route.json"
DECISIONS_PATH = REPO_ROOT / "data" / "act1_decisions.json"
BUILDS_PATH = REPO_ROOT / "data" / "build_overview.tsv"
BUILD_LEVELS_PATH = REPO_ROOT / "data" / "build_levels.tsv"
BUILD_GEAR_PATH = REPO_ROOT / "data" / "build_gear.tsv"
SOURCE_URL = (
    "https://docs.google.com/spreadsheets/d/"
    "1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0"
)


@lru_cache(maxsize=1)
def load_route() -> list[RouteCheckpoint]:
    fights = {row["id"]: row for row in json.loads(FIGHTS_PATH.read_text(encoding="utf-8"))}
    reviewed = json.loads(ROUTE_PATH.read_text(encoding="utf-8"))
    decisions = json.loads(DECISIONS_PATH.read_text(encoding="utf-8"))
    checkpoints: list[RouteCheckpoint] = []
    for route in reviewed:
        fight = fights[route["id"]]
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
                source={"sheet": "Act 1 - fights + Act 1 - Notes", "row": route["sourceRow"], "url": SOURCE_URL},
            )
        )
    return sorted(checkpoints, key=lambda item: item.route_order)


@lru_cache(maxsize=1)
def load_gear() -> list[BuildGear]:
    """All reviewed gear rows — the single parse of build_gear.tsv.

    Consumed per-build here (filtered into BuildSummary.gear) and item-wise by
    map_data to place Act 1 item markers, so both payloads stay on one vocabulary.
    """
    with BUILD_GEAR_PATH.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    return [
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
        )
        for row in rows
    ]


@lru_cache(maxsize=1)
def load_builds() -> list[BuildSummary]:
    with BUILDS_PATH.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    with BUILD_LEVELS_PATH.open(newline="", encoding="utf-8") as handle:
        level_rows = list(csv.DictReader(handle, delimiter="\t"))
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
                )
                for level in level_rows if level["Build ID"] == row["Build ID"]
            ],
            gear=[item for item in gear if row["Build ID"] in item.build_ids],
        )
        for row in rows
    ]


def checkpoint_by_id(checkpoint_id: str) -> RouteCheckpoint:
    for checkpoint in load_route():
        if checkpoint.id == checkpoint_id:
            return checkpoint
    raise KeyError(checkpoint_id)


def _route_phase(checkpoint: RouteCheckpoint) -> int:
    return {
        "Nautiloid": 0,
        "Underdark": 2,
        "Grymforge": 3,
        "Crèche Y'llek": 4,
    }.get(checkpoint.region, 1)


def next_checkpoint(
    completed: set[str], skipped: set[str] | None = None, party_level: int = 1
) -> RouteCheckpoint | None:
    skipped = skipped or set()
    resolved = completed | skipped
    pending = [checkpoint for checkpoint in load_route() if checkpoint.id not in resolved]
    if not pending:
        return None
    current_phase = min(_route_phase(checkpoint) for checkpoint in pending)
    phase_pending = [checkpoint for checkpoint in pending if _route_phase(checkpoint) == current_phase]
    eligible = [
        checkpoint
        for checkpoint in phase_pending
        if all(prerequisite in resolved for prerequisite in checkpoint.prerequisites)
    ] or phase_pending
    safe = [checkpoint for checkpoint in eligible if checkpoint.minimum_level <= party_level]
    return min(
        safe or eligible,
        key=lambda checkpoint: (abs(checkpoint.minimum_level - party_level), checkpoint.route_order),
    )


def assess_readiness(request: ReadinessRequest) -> ReadinessResponse:
    checkpoint = checkpoint_by_id(request.checkpoint_id)
    levels = [member.level for member in request.party]
    party_level = min(levels) if levels else 1
    completed = set(request.completed_checkpoint_ids)
    checked = set(request.checked_preparation)
    blockers: list[str] = []
    warnings: list[str] = []
    build_actions: list[str] = []

    if party_level < checkpoint.minimum_level:
        blockers.append(f"Lowest party member is level {party_level}; guide minimum is level {checkpoint.minimum_level}.")
    missing_prerequisites = [item for item in checkpoint.prerequisites if item not in completed]
    if missing_prerequisites:
        names = [checkpoint_by_id(item).name for item in missing_prerequisites]
        blockers.append("Unresolved route prerequisites: " + ", ".join(names))
    missing_preparation = [item for item in checkpoint.preparation if item not in checked]
    if missing_preparation:
        warnings.append(f"{len(missing_preparation)} preparation item(s) are not confirmed.")
    warnings.extend(checkpoint.irreversible_warnings)

    builds = {build.id: build for build in load_builds()}
    assumed_build_setup: list[str] = []
    for member in request.party:
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
                *(f"{item.item} {item.why} {item.acquisition}" for item in build.gear),
            ]
        )
        if level_plan:
            build_actions.append(f"{member.name} L{member.level} ({build.name}): {level_plan.take}; {level_plan.tactics}")
        elif build.levels:
            warnings.append(f"{member.name}'s reviewed {build.name} plan ends at level {build.levels[-1].level}.")

    capability_terms = ["silence", "calm emotions", "sanctuary", "command", "bludgeoning", "fire", "counterspell", "initiative", "control"]
    requested_text = " ".join([checkpoint.advice, *checkpoint.preparation]).lower()
    recorded_capabilities = " ".join(
        [*(tag for member in request.party for tag in member.prepared_tags), *assumed_build_setup]
    ).lower()
    for capability in capability_terms:
        if capability in requested_text and capability not in recorded_capabilities:
            warnings.append(f"Party capability not recorded: {capability}. Confirm the party has it or choose an alternative plan.")

    status = "blocked" if blockers else ("danger" if checkpoint.irreversible_warnings else ("caution" if warnings else "ready"))
    next_actions = blockers[:2] + missing_preparation[:3] + build_actions[:2]
    if not next_actions:
        next_actions = ["Confirm the pre-fight checklist, then start the encounter on your terms."]
    return ReadinessResponse(
        status=status,
        party_level=party_level,
        minimum_level=checkpoint.minimum_level,
        blockers=blockers,
        warnings=warnings,
        next_actions=next_actions,
    )
