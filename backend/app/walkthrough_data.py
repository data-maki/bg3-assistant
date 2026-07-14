import json
from functools import lru_cache

from .models import WalkthroughDependency, WalkthroughStep
from .paths import resource_root


WALKTHROUGH_PATH = resource_root() / "data" / "act1_walkthrough.json"

SOURCES = {
    "sheet": (
        "Act 1 fight guide",
        "https://docs.google.com/spreadsheets/d/1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0",
    ),
    "reddit": (
        "Act 1 Honor Mode in-depth guide",
        "https://www.reddit.com/r/BaldursGate3/comments/18of2fz/bg3_honor_mode_indepth_guide_for_act_i/",
    ),
    "reddit_dialogue": (
        "Honor Mode run-ending dialogue reports",
        "https://www.reddit.com/r/BaldursGate3/comments/1pi3isl/can_you_guys_share_some_honor_run_killing/",
    ),
    "steam": (
        "Comprehensive 3 Man Honor Mode Walkthrough",
        "https://steamcommunity.com/sharedfiles/filedetails/?id=3146320940",
    ),
    "tavern": (
        "Honor Mode strategy and tradeoffs",
        "https://tavernrpg.com/threads/bg3-honour-mode-strategy-tactics-many-spoilers.388/",
    ),
    "wiki": (
        "BG3 Wiki time-sensitive activities",
        "https://bg3.wiki/wiki/Time-sensitive_activities",
    ),
    "wiki_shovel": (
        "BG3 Wiki — Shovel",
        "https://bg3.wiki/wiki/Shovel_(familiar)",
    ),
    "wiki_thay": (
        "BG3 Wiki — Necromancy of Thay",
        "https://bg3.wiki/wiki/Necromancy_of_Thay",
    ),
    "wiki_sussur": (
        "BG3 Wiki — Finish the Masterwork Weapon",
        "https://bg3.wiki/wiki/Finish_the_Masterwork_Weapon",
    ),
    "wiki_mourning": (
        "BG3 Wiki — Mourning Frost",
        "https://bg3.wiki/wiki/Mourning_Frost",
    ),
    "wiki_lathander": (
        "BG3 Wiki — The Blood of Lathander",
        "https://bg3.wiki/wiki/The_Blood_of_Lathander",
    ),
}


@lru_cache(maxsize=1)
def load_walkthrough() -> list[WalkthroughStep]:
    rows = json.loads(WALKTHROUGH_PATH.read_text(encoding="utf-8"))
    titles = {row["id"]: row["title"] for row in rows}
    steps = []
    for raw in rows:
        row = dict(raw)
        source_key = row.pop("source")
        source_label, source_url = SOURCES[source_key]
        explicit = {item["stepId"]: item for item in row.get("dependencies", [])}
        dependencies = []
        for prerequisite_id in row.get("prerequisites", []):
            dependency = explicit.pop(prerequisite_id, None) or {
                "stepId": prerequisite_id,
                "kind": "resolution_required",
                "reason": f"Resolve {titles.get(prerequisite_id, prerequisite_id)} first.",
            }
            dependencies.append(dependency)
        dependencies.extend(explicit.values())
        row["dependencies"] = dependencies
        steps.append(WalkthroughStep(**row, source_label=source_label, source_url=source_url))
    ordered = sorted(steps, key=lambda step: step.order)
    validate_walkthrough(ordered)
    return ordered


def validate_walkthrough(steps: list[WalkthroughStep]) -> None:
    by_id = {step.id: step for step in steps}
    if len(by_id) != len(steps):
        raise ValueError("Walkthrough step ids must be unique")

    graph: dict[str, list[str]] = {step.id: [] for step in steps}
    for step in steps:
        dependency_ids = {dependency.step_id for dependency in step.dependencies}
        if dependency_ids != set(step.prerequisites):
            raise ValueError(f"{step.id} typed dependencies must match prerequisites")
        for dependency in step.dependencies:
            prerequisite = by_id.get(dependency.step_id)
            if prerequisite is None:
                raise ValueError(f"{step.id} references missing dependency {dependency.step_id}")
            if not dependency.reason.strip():
                raise ValueError(f"{step.id} dependency {dependency.step_id} needs a blocker reason")
            if dependency.kind == "outcome_required" and not dependency.required_outcome:
                raise ValueError(f"{step.id} outcome dependency {dependency.step_id} needs an outcome")
            if dependency.kind != "warning_only" and prerequisite.order >= step.order:
                raise ValueError(f"{step.id} dependency {dependency.step_id} must occur earlier")
            if dependency.kind != "warning_only":
                graph[step.id].append(dependency.step_id)

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(step_id: str) -> None:
        if step_id in visiting:
            raise ValueError(f"Walkthrough dependency cycle at {step_id}")
        if step_id in visited:
            return
        visiting.add(step_id)
        for prerequisite_id in graph[step_id]:
            visit(prerequisite_id)
        visiting.remove(step_id)
        visited.add(step_id)

    for step_id in graph:
        visit(step_id)


def _is_completed(status: str | None) -> bool:
    return status in {"done", "completed"}


def dependency_satisfied(
    dependency: WalkthroughDependency,
    statuses: dict[str, str],
    outcomes: dict[str, str] | None = None,
) -> bool:
    status = statuses.get(dependency.step_id)
    if dependency.kind == "warning_only":
        return True
    if dependency.kind == "completion_required":
        return _is_completed(status)
    if dependency.kind == "outcome_required":
        return _is_completed(status) and (outcomes or {}).get(dependency.step_id) == dependency.required_outcome
    return status in {"done", "completed", "skipped"}


def walkthrough_blockers(
    step: WalkthroughStep,
    steps: list[WalkthroughStep],
    statuses: dict[str, str],
    outcomes: dict[str, str] | None = None,
) -> list[str]:
    titles = {item.id: item.title for item in steps}
    blockers = []
    for dependency in step.dependencies:
        if dependency_satisfied(dependency, statuses, outcomes):
            continue
        title = titles.get(dependency.step_id, dependency.step_id)
        if statuses.get(dependency.step_id) == "skipped" and dependency.kind in {"completion_required", "outcome_required"}:
            blockers.append(f"Revisit {title} — {dependency.reason}")
        else:
            blockers.append(dependency.reason)
    return blockers


def recommend_walkthrough_step(
    steps: list[WalkthroughStep],
    statuses: dict[str, str],
    party_level: int,
    outcomes: dict[str, str] | None = None,
) -> WalkthroughStep | None:
    pending = [step for step in steps if statuses.get(step.id) not in {"done", "completed", "skipped"}]
    if not pending:
        return None
    phase_order = min(step.phase_order for step in pending)
    phase = sorted((step for step in pending if step.phase_order == phase_order), key=lambda item: item.order)
    eligible = [step for step in phase if not walkthrough_blockers(step, steps, statuses, outcomes)]
    if not eligible:
        return None
    revisit = next((step for step in eligible if statuses.get(step.id) == "revisit" and step.minimum_level <= party_level), None)
    return revisit or next((step for step in eligible if step.minimum_level <= party_level), eligible[0])


def walkthrough_by_id(step_id: str) -> WalkthroughStep:
    for step in load_walkthrough():
        if step.id == step_id:
            return step
    raise KeyError(step_id)
