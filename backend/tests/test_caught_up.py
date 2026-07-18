"""Mid-run catch-up writes `caughtUp` dispositions from the native app.

The map backend rebuilds `walkthroughProgress` on every map-side save, so it
must read caughtUp as done (map vocabulary) and must not erase or silently
upgrade it when writing back.
"""

from pathlib import Path
from types import SimpleNamespace

from app import stores
from app.models import RunState


def configure_database(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        stores,
        "get_settings",
        lambda: SimpleNamespace(state_database_path=tmp_path / "state.sqlite3", runs_dir=tmp_path),
    )


def seed_snapshot_with_caught_up():
    stores._run_database.save_snapshot({
        "id": "run-1",
        "guideVersion": "test",
        "party": [],
        "roster": [],
        "progress": {},
        "mapRegion": "Wilderness",
        "selectedAct": 1,
        "walkthroughProgress": {
            "step-1": "caughtUp",
            "step-2": "completed",
            "step-3": "skipped",
        },
    })


def test_caught_up_reads_as_done_for_the_map(tmp_path, monkeypatch):
    configure_database(tmp_path, monkeypatch)
    seed_snapshot_with_caught_up()
    state = stores.current_run_state()
    assert state.walkthrough_statuses["step-1"] == "done"
    assert state.walkthrough_statuses["step-2"] == "done"
    assert state.walkthrough_statuses["step-3"] == "skipped"


def test_map_write_preserves_caught_up_and_records_new_completions(tmp_path, monkeypatch):
    configure_database(tmp_path, monkeypatch)
    seed_snapshot_with_caught_up()
    current = stores.current_run_state()
    statuses = dict(current.walkthrough_statuses)
    statuses["step-4"] = "done"  # a genuine map-side completion
    stores.save_run_state(RunState.model_validate({"walkthroughStatuses": statuses}))

    progress = stores._run_database.load_snapshot()["walkthroughProgress"]
    assert progress["step-1"] == "caughtUp"      # not erased, not upgraded
    assert progress["step-2"] == "completed"
    assert progress["step-3"] == "skipped"
    assert progress["step-4"] == "completed"
