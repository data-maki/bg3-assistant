"""Persistent shared state: live player position and web-map run progress.

One tiny lock-guarded JSON document store, two instances. In-memory state is
authoritative; disk persistence is best-effort so a read-only filesystem never
breaks the loop.
"""

import json
import threading
import time

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
_run_state = JsonStore("run_state.json")
_active_marker_sync = JsonStore("active_marker_sync.json")
_confirmed_marker_sync = JsonStore("confirmed_marker_sync.json")


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
    state = _run_state.get()
    if state is None:
        return RunState()
    try:
        return RunState(**state)
    except Exception:
        return RunState()


def save_run_state(state: RunState) -> RunState:
    normalized = RunState(
        equipped=sorted(set(state.equipped)),
        equipped_by_member={
            member_id: sorted(set(item_keys))
            for member_id, item_keys in state.equipped_by_member.items()
        },
        builds=[build for i, build in enumerate(state.builds) if build not in state.builds[:i]],
        done=sorted(set(state.done)),
        party=state.party,
    )
    _run_state.put(normalized.model_dump())
    return normalized


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
