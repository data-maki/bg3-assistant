"""Shared fixtures and helpers for the backend test suite."""

import os
from pathlib import Path

# Tests must exercise the deterministic guide path regardless of the
# developer's environment; a real key here would route chat through the live
# LLM and make assertions network-dependent. Set before any app import so the
# cached Settings never sees the real key.
os.environ["OPENROUTER_API_KEY"] = ""

import pytest

from app import catalog, stores
from app.models import ImportedBuildDraft


@pytest.fixture
def db_path(tmp_path: Path, monkeypatch) -> Path:
    """Point the catalog/run database at a fresh per-test SQLite file."""
    path = tmp_path / "state.sqlite3"
    monkeypatch.setattr(stores.RunDatabase, "path", property(lambda self: path))
    catalog.reset_for_tests()
    yield path
    catalog.reset_for_tests()


def sample_draft() -> ImportedBuildDraft:
    return ImportedBuildDraft.model_validate({
        "name": "Swords Bard",
        "role": "Face and ranged striker",
        "finalSplit": "Bard 12",
        "classProgression": "Bard",
        "startingAbilityScores": {
            "strength": 8,
            "dexterity": 16,
            "constitution": 14,
            "intelligence": 8,
            "wisdom": 10,
            "charisma": 17,
        },
        "playPattern": "Control, then flourish",
        "caveat": "Keep inspiration available",
        "levels": [{
            "level": 4,
            "take": "Bard 4",
            "subclassChoice": "College of Swords",
            "choices": "Ability Improvement: +2 DEX",
            "tactics": "Use Slashing Flourish",
            "confidence": "source",
        }],
        "gear": [{
            "item": "Titanstring Bow",
            "slot": "Ranged",
            "priority": "Core",
            "act": 1,
            "region": "Wilderness",
            "acquisition": "Buy from Brem",
            "why": "Strong ranged damage",
            "minimumLevel": 4,
            "maximumLevel": None,
            "requirement": "",
            "alternative": "Bow of Awareness",
        }],
    })
