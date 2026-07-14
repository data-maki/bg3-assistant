"""Read the optional BG3 telemetry snapshot without making it a dependency.

The producer is a separately installed Script Extender mod. Its file is
untrusted advisory input: malformed, oversized, incompatible, or stale data
must degrade to Vanilla mode and must never mutate route progress.
"""

import json
import os
import time
from pathlib import Path

from pydantic import ValidationError

from .models import TelemetrySnapshot, TelemetryStatus


SCHEMA_VERSION = 1
PRODUCER_ID = "bg3-honor-telemetry"
MAX_SNAPSHOT_BYTES = 1_000_000
ACTIVE_MAX_AGE_SECONDS = 8.0
MAX_RETURNED_EVENTS = 24


def telemetry_file_path() -> Path:
    configured = os.environ.get("BG3_TELEMETRY_FILE")
    if configured:
        return Path(configured).expanduser()
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "BG3HonorAssistant"
        / "telemetry"
        / "events.json"
    )


def ensure_telemetry_directory() -> Path:
    path = telemetry_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def read_telemetry_status(now: float | None = None) -> TelemetryStatus:
    path = ensure_telemetry_directory()
    if not path.exists():
        return TelemetryStatus()

    try:
        stat = path.stat()
        if stat.st_size > MAX_SNAPSHOT_BYTES:
            return _unavailable("Live Events feed rejected: file is too large.")
        raw = json.loads(path.read_text(encoding="utf-8"))
        snapshot = TelemetrySnapshot.model_validate(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValidationError):
        return _unavailable("Live Events feed is unreadable; using Vanilla mode.")

    if snapshot.schema_version != SCHEMA_VERSION:
        return _unavailable(
            f"Live Events schema {snapshot.schema_version} is incompatible; expected {SCHEMA_VERSION}."
        )
    if snapshot.producer_id != PRODUCER_ID:
        return _unavailable("Live Events producer is not recognized; using Vanilla mode.")

    current_time = time.time() if now is None else now
    age = max(0.0, current_time - stat.st_mtime)
    fresh = age <= ACTIVE_MAX_AGE_SECONDS
    events_by_sequence = {
        event.sequence: event
        for event in snapshot.events
        if event.sequence <= snapshot.sequence
    }
    events = sorted(events_by_sequence.values(), key=lambda event: event.sequence)[-MAX_RETURNED_EVENTS:]
    if not fresh:
        return TelemetryStatus(
            available=True,
            stale=True,
            message="Live Events feed is stale; using Vanilla mode.",
            producer_version=snapshot.producer_version,
            session_id=snapshot.session_id,
            last_sequence=snapshot.sequence,
            age_seconds=round(age, 2),
            events=events,
        )
    return TelemetryStatus(
        available=True,
        active=True,
        mode="live_events",
        message="Live Events active • modded run",
        producer_version=snapshot.producer_version,
        session_id=snapshot.session_id,
        last_sequence=snapshot.sequence,
        age_seconds=round(age, 2),
        events=events,
    )


def _unavailable(message: str) -> TelemetryStatus:
    return TelemetryStatus(available=True, message=message)
