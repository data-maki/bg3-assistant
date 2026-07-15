"""Resolve a bounded chat snapshot against trusted local guide data."""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import BuildGear, BuildSummary, ChatRequest, PartyMember, RouteCheckpoint, WalkthroughStep
from .route_data import GUIDE_VERSION, item_key, load_builds
from .walkthrough_data import load_walkthrough, recommend_walkthrough_step, walkthrough_blockers


@dataclass
class ResolvedChatContext:
    scope: str
    selected_act: int
    map_region: str
    route_phase: str
    party_level: int
    active: list[PartyMember]
    inactive: list[PartyMember]
    recommended: WalkthroughStep | None
    focused: WalkthroughStep | None
    current: WalkthroughStep | None
    blockers: list[str]
    prerequisite_chain: list[str] = field(default_factory=list)
    recent_statuses: list[str] = field(default_factory=list)
    build_actions: dict[str, str] = field(default_factory=dict)
    relevant_gear: dict[str, list[BuildGear]] = field(default_factory=dict)
    equipped_by_member: dict[str, list[str]] = field(default_factory=dict)
    equipment_known: bool = False
    equipment_conflicts: list[str] = field(default_factory=list)
    story_outcomes: list[str] = field(default_factory=list)
    walkthrough_outcomes: dict[str, str] = field(default_factory=dict)
    guide_version_mismatch: str | None = None

    def missing_gear(self, member_id: str) -> list[BuildGear]:
        """Reviewed gear this member should pursue and does not own yet.

        The single definition of "missing": deterministic answers and LLM
        grounding must never disagree about what a member still needs.
        """
        owned = set(self.equipped_by_member.get(member_id, []))
        return [
            gear for gear in self.relevant_gear.get(member_id, [])
            if item_key(gear.item) not in owned and gear.item not in owned
        ]

    def grounding_lines(self, checkpoint: RouteCheckpoint) -> list[str]:
        """Concise, authority-labelled state for deterministic or LLM chat."""
        lines = [
            f"[Guide fact] Guide version: {GUIDE_VERSION}.",
            f"[Player state] Act {self.selected_act}; region {self.map_region}; phase {self.route_phase}.",
            f"[Player state] Active party: {', '.join(f'{member.name} L{member.level}' for member in self.active) or 'none'}.",
        ]
        if self.recommended:
            lines.append(f"[Assistant suggestion] Safe recommendation: {self.recommended.title} ({self.recommended.id}).")
        if self.focused:
            lines.append(f"[Player state] Player focus: {self.focused.title} ({self.focused.id}).")
        if self.blockers:
            lines.append("[Guide fact] Focus blockers: " + "; ".join(self.blockers))
        if self.prerequisite_chain:
            lines.append("[Guide fact] Prerequisite chain: " + " → ".join(self.prerequisite_chain))
        if self.recent_statuses:
            lines.append("[Player-confirmed progress] " + "; ".join(self.recent_statuses))
        for member in self.active:
            if action := self.build_actions.get(member.id):
                lines.append(f"[Reviewed build] {member.name}: {action}")
        if self.story_outcomes:
            lines.append("[Player-confirmed outcome] " + "; ".join(self.story_outcomes))
        if self.equipment_known:
            for member in self.active:
                owned = self.equipped_by_member.get(member.id, [])
                if owned:
                    lines.append(f"[Player-confirmed equipment] {member.name}: {', '.join(owned)}")
                if missing := [gear.item for gear in self.missing_gear(member.id)]:
                    lines.append(f"[Reviewed loadout] {member.name} missing/current pursuits: {', '.join(missing[:3])}")
        else:
            lines.append("[Unknown] Equipment ownership has not been confirmed.")
        relevant_inactive = [member for member in self.inactive if member.status in {"dead", "departed", "unavailable"}]
        if self.scope == "party":
            relevant_inactive = self.inactive
        if relevant_inactive:
            lines.append("[Player state] Inactive roster: " + ", ".join(f"{member.name} ({member.status})" for member in relevant_inactive))
        lines.extend(f"[Unknown] {conflict}" for conflict in self.equipment_conflicts)
        if self.guide_version_mismatch:
            lines.append(f"[Unknown] {self.guide_version_mismatch}")
        return lines


def _valid_step(step_id: str | None, by_id: dict[str, WalkthroughStep]) -> WalkthroughStep | None:
    return by_id.get(step_id) if step_id else None


def _available_gear(build_id: str, level: int, act: int, builds: dict[str, BuildSummary]) -> list[BuildGear]:
    build = builds.get(build_id)
    if not build:
        return []
    return [
        gear for gear in build.gear
        if gear.act <= act
        and gear.minimum_level <= level
        and (gear.maximum_level is None or level <= gear.maximum_level)
    ]


def _prerequisite_chain(step: WalkthroughStep | None, by_id: dict[str, WalkthroughStep]) -> list[str]:
    if not step:
        return []
    ordered: list[str] = []
    seen: set[str] = set()

    def visit(current: WalkthroughStep) -> None:
        for dependency in current.dependencies:
            prerequisite = by_id.get(dependency.step_id)
            if not prerequisite or prerequisite.id in seen:
                continue
            visit(prerequisite)
            seen.add(prerequisite.id)
            ordered.append(prerequisite.title)

    visit(step)
    return ordered


def resolve_chat_context(
    checkpoint: RouteCheckpoint,
    request: ChatRequest,
    requested_step: WalkthroughStep | None = None,
) -> ResolvedChatContext:
    """Trust player state values, but re-resolve every guide identifier locally."""
    snapshot = request.context
    steps = load_walkthrough()
    by_id = {step.id: step for step in steps}
    statuses = snapshot.walkthrough_statuses if snapshot else {}
    outcomes = snapshot.walkthrough_outcomes if snapshot else {}
    roster = snapshot.roster if snapshot and snapshot.roster else request.party
    active = [member for member in roster if (member.status or "active") == "active"][:4]
    inactive = [member for member in roster if (member.status or "active") != "active"]
    party_level = min((member.level for member in active), default=1)

    recommended = recommend_walkthrough_step(steps, statuses, party_level, outcomes) if snapshot else None
    focused = _valid_step(snapshot.focused_step_id, by_id) if snapshot else requested_step
    current = focused or requested_step or recommended
    blockers = walkthrough_blockers(current, steps, statuses, outcomes) if current else []
    if current and current.minimum_level > party_level:
        blockers.append(f"Active party floor is L{party_level}; guide minimum for {current.title} is L{current.minimum_level}.")
    prerequisite_chain = _prerequisite_chain(current, by_id)
    recent_statuses = [
        f"{step.title}: {statuses[step.id]}"
        for step in reversed(steps) if step.id in statuses
    ][:5]

    builds = {build.id: build for build in load_builds()}
    build_actions: dict[str, str] = {}
    relevant_gear: dict[str, list[BuildGear]] = {}
    selected_act = snapshot.selected_act if snapshot else 1
    for member in active:
        if not member.build_id or member.build_id not in builds:
            continue
        build = builds[member.build_id]
        level = next((row for row in build.levels if row.level == member.level), None)
        if level:
            build_actions[member.id] = f"L{member.level} · {build.name} — {level.take}: {level.choices or level.tactics}"
        relevant_gear[member.id] = _available_gear(member.build_id, member.level, selected_act, builds)

    equipped = snapshot.equipped_by_member if snapshot else {}
    equipment_known = bool(snapshot and snapshot.equipment_ownership_known)

    owners: dict[str, list[str]] = {}
    names = {member.id: member.name for member in roster}
    for member_id, item_keys in equipped.items():
        for key in item_keys:
            owners.setdefault(key, []).append(member_id)
    conflicts = [
        f"Conflicting unique equipment '{key}' is assigned to {', '.join(names.get(owner, owner) for owner in member_ids)}; confirm one owner."
        for key, member_ids in owners.items() if len(set(member_ids)) > 1
    ]

    mismatch = None
    if snapshot and snapshot.guide_version and snapshot.guide_version != GUIDE_VERSION:
        mismatch = f"Run uses guide {snapshot.guide_version}; backend guide is {GUIDE_VERSION}."

    return ResolvedChatContext(
        scope=snapshot.scope if snapshot else "current",
        selected_act=selected_act,
        map_region=snapshot.map_region if snapshot else checkpoint.region,
        route_phase=snapshot.route_phase if snapshot else (current.phase if current else "unknown"),
        party_level=party_level,
        active=active,
        inactive=inactive,
        recommended=recommended,
        focused=focused,
        current=current,
        blockers=blockers,
        prerequisite_chain=prerequisite_chain,
        recent_statuses=recent_statuses,
        build_actions=build_actions,
        relevant_gear=relevant_gear,
        equipped_by_member=equipped,
        equipment_known=equipment_known,
        equipment_conflicts=conflicts,
        story_outcomes=snapshot.story_outcomes if snapshot else [],
        walkthrough_outcomes=outcomes,
        guide_version_mismatch=mismatch,
    )
