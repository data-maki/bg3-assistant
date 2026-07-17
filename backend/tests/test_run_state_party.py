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


def seed_native_snapshot():
    stores._run_database.save_snapshot({
        "id": "run-1",
        "guideVersion": "test",
        "party": [],
        "roster": [{
            "id": "tav",
            "name": "Tav",
            "level": 4,
            "buildId": "MO-OH",
            "preparedTags": [],
            "status": "active",
            "abilityScores": {
                "strength": 10, "dexterity": 16, "constitution": 15,
                "intelligence": 8, "wisdom": 16, "charisma": 8,
            },
            "abilityModifiers": [{
                "id": "modifier-1",
                "ability": "strength",
                "kind": "temporary",
                "mode": "minimum",
                "value": 21,
                "source": "Elixir of Hill Giant Strength",
                "planSourceId": "hill-giant-elixir",
            }],
            "usesBuildAbilityScores": True,
            "appliedAbilitySetupId": "creation",
            "futureNativeField": {"keep": True},
        }],
        "progress": {},
        "mapRegion": "Wilderness",
        "selectedAct": 1,
    })


def test_partial_browser_member_update_preserves_native_ability_state(tmp_path, monkeypatch):
    configure_database(tmp_path, monkeypatch)
    seed_native_snapshot()
    partial = RunState.model_validate({
        "roster": [{"id": "tav", "name": "Tav", "level": 5, "status": "active"}],
    })
    stores.save_run_state(partial)
    member = stores._run_database.load_snapshot()["roster"][0]
    assert member["level"] == 5
    assert member["abilityModifiers"][0]["planSourceId"] == "hill-giant-elixir"
    assert member["usesBuildAbilityScores"] is True
    assert member["appliedAbilitySetupId"] == "creation"
    assert member["futureNativeField"] == {"keep": True}


def test_explicit_browser_clear_removes_ability_state(tmp_path, monkeypatch):
    configure_database(tmp_path, monkeypatch)
    seed_native_snapshot()
    clear = RunState.model_validate({
        "roster": [{
            "id": "tav", "name": "Tav", "level": 4, "status": "active",
            "abilityModifiers": [], "usesBuildAbilityScores": False,
            "appliedAbilitySetupId": None,
        }],
    })
    stores.save_run_state(clear)
    member = stores._run_database.load_snapshot()["roster"][0]
    assert member["abilityModifiers"] == []
    assert member["usesBuildAbilityScores"] is False
    assert member["appliedAbilitySetupId"] is None
    assert member["futureNativeField"] == {"keep": True}
