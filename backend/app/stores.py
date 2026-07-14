"""Persistent shared state for the native overlay and localhost map.

The complete run lives in the native-compatible SQLite snapshot. Small,
non-run diagnostics such as current map position remain best-effort JSON.
"""

import json
import sqlite3
import threading
import time
import uuid
from pathlib import Path

from .config import get_settings
from .models import MarkerSyncPreview, PlayerPosition, RunState


class JsonStore:
    def __init__(self, filename: str) -> None:
        self._filename = filename
        self._lock = threading.Lock()
        self._state: dict | None = None
        self._loaded = False

    def get(self) -> dict | None:
        with self._lock:
            if not self._loaded:
                self._loaded = True
                try:
                    self._state = json.loads((get_settings().runs_dir / self._filename).read_text())
                except Exception:
                    self._state = None
            return self._state

    def put(self, state: dict) -> dict:
        with self._lock:
            self._state = state
            self._loaded = True
            try:
                path = get_settings().runs_dir / self._filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(state))
            except Exception:
                pass
            return state


_position = JsonStore("position.json")
_legacy_run_state = JsonStore("run_state.json")
_active_marker_sync = JsonStore("active_marker_sync.json")
_confirmed_marker_sync = JsonStore("confirmed_marker_sync.json")


class RunDatabase:
    """SQLite authority shared with the native app.

    The native snapshot remains lossless. Web-map changes merge only the fields
    it owns, so browser progress cannot erase native-only settings or evidence.
    """

    @property
    def path(self) -> Path:
        settings = get_settings()
        return settings.state_database_path or settings.runs_dir / "state.sqlite3"

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=5.0)
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS runs(
                run_id TEXT PRIMARY KEY,
                snapshot_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        connection.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS one_active_run ON runs(is_active) WHERE is_active = 1"
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS run_revisions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                snapshot_json TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        return connection

    def load_snapshot(self) -> dict | None:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT snapshot_json FROM runs WHERE is_active = 1 ORDER BY updated_at DESC LIMIT 1"
            ).fetchone()
        if not row:
            return None
        try:
            value = json.loads(row[0])
            return value if isinstance(value, dict) else None
        except (TypeError, json.JSONDecodeError):
            return None

    def save_snapshot(self, snapshot: dict) -> None:
        run_id = str(snapshot.get("id") or uuid.uuid4())
        snapshot["id"] = run_id
        encoded = json.dumps(snapshot, separators=(",", ":"), sort_keys=True)
        now = time.time()
        with self.connect() as connection:
            connection.execute("UPDATE runs SET is_active = 0 WHERE is_active = 1")
            connection.execute(
                """
                INSERT INTO runs(run_id, snapshot_json, updated_at, is_active) VALUES(?, ?, ?, 1)
                ON CONFLICT(run_id) DO UPDATE SET
                    snapshot_json = excluded.snapshot_json,
                    updated_at = excluded.updated_at,
                    is_active = 1
                """,
                (run_id, encoded, now),
            )
            connection.execute(
                "INSERT INTO run_revisions(run_id, snapshot_json, created_at) VALUES(?, ?, ?)",
                (run_id, encoded, now),
            )
            connection.execute(
                """
                DELETE FROM run_revisions
                WHERE run_id = ? AND id NOT IN (
                    SELECT id FROM run_revisions WHERE run_id = ? ORDER BY id DESC LIMIT 20
                )
                """,
                (run_id, run_id),
            )


_run_database = RunDatabase()


def current_position() -> PlayerPosition | None:
    state = _position.get()
    if state is None:
        return None
    try:
        return PlayerPosition(**state)
    except Exception:
        return None


def publish_position(
    lat: float, lng: float, source: str, confidence: float = 0.0, zoom: float | None = None
) -> PlayerPosition:
    position = PlayerPosition(
        lat=lat, lng=lng, source=source, confidence=confidence, zoom=zoom, updated_at=time.time()
    )
    _position.put(position.model_dump())
    return position


def current_run_state() -> RunState:
    snapshot = _run_database.load_snapshot()
    if snapshot is not None:
        return _run_state_from_snapshot(snapshot)
    state = _legacy_run_state.get()
    if state is None:
        return RunState()
    try:
        parsed = RunState(**state)
        return save_run_state(parsed)
    except Exception:
        return RunState()


def save_run_state(state: RunState) -> RunState:
    snapshot = _run_database.load_snapshot() or {
        "id": str(uuid.uuid4()),
        "guideVersion": "",
        "party": [],
        "progress": {},
        "mapRegion": "Wilderness",
        "selectedAct": 1,
    }
    current = _run_state_from_snapshot(snapshot)
    for field_name in state.model_fields_set:
        setattr(current, field_name, getattr(state, field_name))
    roster_source = current.party if "party" in state.model_fields_set and "roster" not in state.model_fields_set else (current.roster or current.party)
    roster = _normalize_roster(roster_source)
    active_party = [member for member in roster if member.status == "active"][:4]
    normalized = RunState(
        equipped_by_member={
            member_id: sorted(set(item_keys))
            for member_id, item_keys in current.equipped_by_member.items()
        },
        builds=[build for i, build in enumerate(current.builds) if build not in current.builds[:i]],
        done=sorted(set(current.done)),
        walkthrough_statuses={
            step_id: status
            for step_id, status in current.walkthrough_statuses.items()
            if status in {"done", "skipped", "revisit"}
        },
        walkthrough_outcomes=current.walkthrough_outcomes,
        focused_walkthrough_step_id=current.focused_walkthrough_step_id,
        party=active_party,
        roster=roster,
        story_outcomes=list(dict.fromkeys(current.story_outcomes)),
        include_camp_plans=current.include_camp_plans,
    )
    _merge_run_state_into_snapshot(snapshot, normalized)
    _run_database.save_snapshot(snapshot)
    return _run_state_from_snapshot(snapshot)


def _run_state_from_snapshot(snapshot: dict) -> RunState:
    raw_statuses = snapshot.get("walkthroughProgress") or {}
    focused = snapshot.get("focusedWalkthroughStepId")
    statuses = {
        step_id: "done" if status == "completed" else status
        for step_id, status in raw_statuses.items()
        if status in {"completed", "skipped"}
    }
    if focused and focused not in statuses:
        statuses[focused] = "revisit"
    roster = _normalize_roster([
        _map_party_member(member) for member in (snapshot.get("roster") or snapshot.get("party") or [])
    ])
    party = [member for member in roster if member.status == "active"][:4]
    builds = snapshot.get("activeBuilds") or [
        member.build_id for member in roster if member.build_id
    ]
    derived_done: list[str] = []
    try:
        from .walkthrough_data import load_walkthrough
        derived_done = [
            step.checkpoint_id
            for step in load_walkthrough()
            if step.checkpoint_id and statuses.get(step.id) == "done"
        ]
    except Exception:
        pass
    return RunState(
        equipped_by_member=snapshot.get("equippedByMember") or {},
        builds=list(dict.fromkeys(builds)),
        done=sorted(set([*(snapshot.get("doneFightIds") or []), *derived_done])),
        walkthrough_statuses=statuses,
        walkthrough_outcomes=snapshot.get("walkthroughOutcomes") or {},
        focused_walkthrough_step_id=focused,
        party=party,
        roster=roster,
        story_outcomes=snapshot.get("storyOutcomes") or [],
        include_camp_plans=bool(snapshot.get("includeCampPlans")),
    )


def _merge_run_state_into_snapshot(snapshot: dict, state: RunState) -> None:
    progress: dict[str, str] = {}
    focus = state.focused_walkthrough_step_id
    for step_id, status in state.walkthrough_statuses.items():
        if status == "done":
            progress[step_id] = "completed"
        elif status == "skipped":
            progress[step_id] = "skipped"
        elif status == "revisit":
            focus = step_id
    snapshot.update({
        "party": [member.model_dump(by_alias=True, exclude_none=True) for member in state.party],
        "roster": [member.model_dump(by_alias=True, exclude_none=True) for member in state.roster],
        "walkthroughProgress": progress,
        "walkthroughOutcomes": state.walkthrough_outcomes,
        "focusedWalkthroughStepId": focus,
        "storyOutcomes": state.story_outcomes,
        "includeCampPlans": state.include_camp_plans,
        "equippedByMember": state.equipped_by_member,
        "equipmentOwnershipKnown": bool(state.equipped_by_member) or bool(snapshot.get("equipmentOwnershipKnown")),
        "activeBuilds": state.builds,
        "doneFightIds": state.done,
    })


def _map_party_member(value: dict):
    from .models import MapPartyMember
    return MapPartyMember(**value)


def _normalize_roster(members: list) -> list:
    defaults = [
        ("tav", "Tav", None, True, "active"),
        ("shadowheart", "Shadowheart", "Cleric", False, "active"),
        ("laezel", "Lae'zel", "Fighter", False, "active"),
        ("astarion", "Astarion", "Rogue", False, "active"),
        ("gale", "Gale", "Wizard", False, "camp"),
        ("wyll", "Wyll", "Warlock", False, "camp"),
        ("karlach", "Karlach", "Barbarian", False, "camp"),
    ]
    roster = [member.model_copy(deep=True) for member in members]
    had_members = bool(roster)
    if members and all(member.status == "active" for member in roster):
        for index in range(4, len(roster)):
            roster[index].status = "camp"
    existing = {member.name.casefold() for member in roster}
    baseline_level = max((member.level for member in roster), default=1)
    from .models import MapPartyMember
    for member_id, name, class_name, is_custom, status in defaults:
        if name.casefold() in existing:
            continue
        roster.append(MapPartyMember(
            id=member_id,
            name=name,
            level=baseline_level,
            class_name=class_name,
            status="camp" if had_members else status,
            is_custom=is_custom,
        ))
    active_count = 0
    for member in roster:
        if member.status != "active":
            continue
        active_count += 1
        if active_count > 4:
            member.status = "camp"
    return roster


def activate_marker_sync(preview: MarkerSyncPreview) -> MarkerSyncPreview:
    _active_marker_sync.put(preview.model_dump())
    return preview


def current_marker_sync() -> MarkerSyncPreview | None:
    state = _active_marker_sync.get()
    if state is None:
        return None
    try:
        return MarkerSyncPreview(**state)
    except Exception:
        return None


def marker_sync_confirmed(fingerprint: str) -> bool:
    state = _confirmed_marker_sync.get() or {}
    return fingerprint in set(state.get("fingerprints") or [])


def confirm_marker_sync(fingerprint: str) -> None:
    state = _confirmed_marker_sync.get() or {}
    fingerprints = list(dict.fromkeys([*(state.get("fingerprints") or []), fingerprint]))[-24:]
    _confirmed_marker_sync.put({"fingerprints": fingerprints})
