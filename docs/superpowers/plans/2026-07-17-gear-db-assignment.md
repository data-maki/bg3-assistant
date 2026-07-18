# Gear DB, Deterministic Assignment, and Slot Swapping — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move builds/items into relational SQLite tables (seeded once from the checked-in TSVs, grown by imports), resolve gear contention deterministically by build-assignment recency with manual overrides, and let players swap any Loadout slot to another valid catalog item with effect explanations.

**Architecture:** A new `backend/app/catalog.py` owns four tables (`items`, `builds`, `build_levels`, `build_items`) inside the existing `state.sqlite3`, seeds them from the TSV exports exactly once (version-guarded), migrates legacy `custom_loadouts` JSON rows, and becomes what `/api/act1/route`, map markers, and the new `GET /api/items` serve from. On the Mac side, `HonorRun` gains `buildAssignedAt` / `gearAssignmentOverrides` / `plannedSlotOverrides`, a pure `GearLogic.assignments` resolver decides who gets contested items, and the Loadout drawer gains a "Change pick" catalog picker plus a "Give to X" override action.

**Tech Stack:** Python 3.12 / FastAPI / sqlite3 / pytest (run via `uv`), SwiftUI (macOS, Swift Package in `mac/`), XCTest target `BG3AssistantTests` (typecheck locally with `swift build`; XCTest is unavailable in the local CLT toolchain, so logic is verified with a scratchpad swiftc runner — see Task 7 Step 4).

**Read the spec first:** `docs/superpowers/specs/2026-07-17-gear-db-assignment-design.md`

**Concurrent-workspace warning:** This repo sees concurrent edits (see TOOLCALLING_FAILURES.md). Line numbers drift; anchor every edit on function/type names, and re-read a file immediately before modifying it.

---

### Task 1: Catalog schema + TSV seed (backend)

**Files:**
- Create: `backend/app/catalog.py`
- Test: `backend/tests/test_catalog.py`

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/test_catalog.py
import json
import sqlite3
import time

import pytest

from app import catalog, stores
from app.route_data import GUIDE_VERSION, load_builds as tsv_builds, load_gear as tsv_gear


@pytest.fixture
def db_path(tmp_path, monkeypatch):
    path = tmp_path / "state.sqlite3"
    monkeypatch.setattr(stores.RunDatabase, "path", property(lambda self: path))
    catalog.reset_for_tests()
    yield path
    catalog.reset_for_tests()


def table_count(path, table):
    with sqlite3.connect(path) as connection:
        return connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def test_seed_populates_tables(db_path):
    catalog.ensure_seeded()
    assert table_count(db_path, "builds") == len(tsv_builds())
    assert table_count(db_path, "build_levels") == sum(len(b.levels) for b in tsv_builds())
    # one build_items row per (build, gear row) pairing
    assert table_count(db_path, "build_items") == sum(len(b.gear) for b in tsv_builds())
    # items dedupe across builds/acts
    assert table_count(db_path, "items") == len({g.item for g in tsv_gear()})


def test_seed_is_idempotent(db_path):
    catalog.ensure_seeded()
    first = table_count(db_path, "build_items")
    catalog.reset_for_tests()
    catalog.ensure_seeded()
    assert table_count(db_path, "build_items") == first


def test_seed_records_version_and_item_facts(db_path):
    catalog.ensure_seeded()
    with sqlite3.connect(db_path) as connection:
        connection.row_factory = sqlite3.Row
        version = connection.execute(
            "SELECT value FROM settings WHERE key = 'catalog_seed_version'"
        ).fetchone()
        assert version["value"] == GUIDE_VERSION
        row = connection.execute(
            "SELECT * FROM items WHERE item_key = 'titanstring-bow'"
        ).fetchone()
        assert row["slot"] == "Ranged"
        assert row["act"] == 1
        assert "Zhentarim" in row["region"]
        assert row["effect"]  # enrichment joined from item_effects.json
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v`
Expected: FAIL with `ImportError: cannot import name 'catalog'`

- [ ] **Step 3: Implement `catalog.py` (schema, seed, version guard)**

```python
# backend/app/catalog.py
"""Relational catalog: items, builds, build_levels, build_items.

Authoritative store for builds and items inside state.sqlite3. Seeded once
from the checked-in TSV exports (guarded by the catalog_seed_version
setting), then grown by build imports. The Google Sheet's per-build tabs
(everything after "Inspiration on the go") are no longer a data source.
"""
import json
import re
import sqlite3
import time
import urllib.parse
import urllib.request

from . import route_data, stores
from .models import (
    AbilityScores,
    AbilityTargetScores,
    BuildGear,
    BuildLevel,
    BuildSummary,
    CatalogItem,
    ImportedBuild,
    ImportedLoadout,
)
from .route_data import GUIDE_VERSION, item_key

SCHEMA = """
CREATE TABLE IF NOT EXISTS items(
    item_key TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    slot TEXT NOT NULL,
    act INTEGER NOT NULL,
    region TEXT NOT NULL DEFAULT '',
    acquisition TEXT NOT NULL DEFAULT '',
    game_x INTEGER,
    game_y INTEGER,
    map_objective INTEGER NOT NULL DEFAULT 1,
    effect TEXT NOT NULL DEFAULT '',
    acquire TEXT NOT NULL DEFAULT '',
    wiki TEXT NOT NULL DEFAULT '',
    icon TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS builds(
    build_id TEXT PRIMARY KEY,
    import_id TEXT,
    name TEXT NOT NULL,
    honor_status TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL DEFAULT '',
    final_split TEXT NOT NULL DEFAULT '',
    class_progression TEXT NOT NULL DEFAULT '',
    starting_abilities TEXT NOT NULL DEFAULT '',
    starting_scores_json TEXT,
    target_scores_json TEXT,
    target_ability_note TEXT NOT NULL DEFAULT '',
    ability_setups_json TEXT NOT NULL DEFAULT '[]',
    ability_sources_json TEXT NOT NULL DEFAULT '[]',
    play_pattern TEXT NOT NULL DEFAULT '',
    caveat TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL CHECK(origin IN ('seed', 'import')),
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS build_levels(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    build_id TEXT NOT NULL REFERENCES builds(build_id) ON DELETE CASCADE,
    level INTEGER NOT NULL,
    take TEXT NOT NULL DEFAULT '',
    subclass_choice TEXT NOT NULL DEFAULT '',
    choices TEXT NOT NULL DEFAULT '',
    tactics TEXT NOT NULL DEFAULT '',
    confidence TEXT NOT NULL DEFAULT '',
    ability_score_reset_json TEXT,
    UNIQUE(build_id, level)
);
CREATE TABLE IF NOT EXISTS build_items(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    build_id TEXT NOT NULL REFERENCES builds(build_id) ON DELETE CASCADE,
    item_key TEXT NOT NULL REFERENCES items(item_key),
    act INTEGER NOT NULL,
    priority TEXT NOT NULL DEFAULT '',
    minimum_level INTEGER NOT NULL DEFAULT 1,
    maximum_level INTEGER,
    requirement TEXT NOT NULL DEFAULT '',
    alternative TEXT NOT NULL DEFAULT '',
    why TEXT NOT NULL DEFAULT '',
    UNIQUE(build_id, item_key, act)
);
"""

_seeded = False


def reset_for_tests() -> None:
    global _seeded
    _seeded = False


def _connect() -> sqlite3.Connection:
    connection = stores.RunDatabase().connect()
    connection.row_factory = sqlite3.Row
    connection.executescript(SCHEMA)
    return connection


def ensure_seeded() -> None:
    global _seeded
    if _seeded:
        return
    with _connect() as connection:
        row = connection.execute(
            "SELECT value FROM settings WHERE key = 'catalog_seed_version'"
        ).fetchone()
        if row is None or row["value"] != GUIDE_VERSION:
            _seed(connection)
            connection.execute(
                """
                INSERT INTO settings(key, value, updated_at) VALUES('catalog_seed_version', ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                (GUIDE_VERSION, time.time()),
            )
        _migrate_custom_loadouts(connection)
    _seeded = True


def _upsert_item(connection: sqlite3.Connection, gear: BuildGear) -> None:
    connection.execute(
        """
        INSERT INTO items(item_key, name, slot, act, region, acquisition, game_x, game_y,
                          map_objective, effect, acquire, wiki, icon, source, updated_at)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(item_key) DO UPDATE SET
            name = excluded.name, slot = excluded.slot, act = excluded.act,
            region = excluded.region, acquisition = excluded.acquisition,
            game_x = excluded.game_x, game_y = excluded.game_y,
            map_objective = excluded.map_objective,
            effect = CASE WHEN excluded.effect != '' THEN excluded.effect ELSE items.effect END,
            acquire = CASE WHEN excluded.acquire != '' THEN excluded.acquire ELSE items.acquire END,
            wiki = CASE WHEN excluded.wiki != '' THEN excluded.wiki ELSE items.wiki END,
            icon = CASE WHEN excluded.icon != '' THEN excluded.icon ELSE items.icon END,
            source = excluded.source, updated_at = excluded.updated_at
        """,
        (
            gear.itemKey if hasattr(gear, "itemKey") else item_key(gear.item),
            re.sub(r"\s*x\d+$", "", gear.item).strip() or gear.item,
            gear.slot, gear.act, gear.region, gear.acquisition,
            gear.game_x, gear.game_y, int(gear.map_objective),
            gear.effect, gear.acquire, gear.wiki, gear.icon, gear.source, time.time(),
        ),
    )


def _insert_build(
    connection: sqlite3.Connection, build: BuildSummary, origin: str,
    source_url: str, import_id: str | None,
) -> None:
    connection.execute("DELETE FROM builds WHERE build_id = ?", (build.id,))
    connection.execute(
        """
        INSERT INTO builds(build_id, import_id, name, honor_status, role, final_split,
            class_progression, starting_abilities, starting_scores_json, target_scores_json,
            target_ability_note, ability_setups_json, ability_sources_json,
            play_pattern, caveat, source_url, origin, created_at)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            build.id, import_id, build.name, build.honor_status, build.role,
            build.final_split, build.class_progression, build.starting_abilities,
            build.starting_ability_scores.model_dump_json() if build.starting_ability_scores else None,
            build.target_ability_scores.model_dump_json() if build.target_ability_scores else None,
            build.target_ability_note,
            json.dumps([item.model_dump(mode="json") for item in build.ability_setups]),
            json.dumps([item.model_dump(mode="json") for item in build.ability_sources]),
            build.play_pattern, build.caveat, source_url, origin, time.time(),
        ),
    )
    for level in build.levels:
        connection.execute(
            """
            INSERT INTO build_levels(build_id, level, take, subclass_choice, choices,
                tactics, confidence, ability_score_reset_json)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(build_id, level) DO NOTHING
            """,
            (
                build.id, level.level, level.take, level.subclass_choice,
                level.choices, level.tactics, level.confidence,
                level.ability_score_reset.model_dump_json() if level.ability_score_reset else None,
            ),
        )
    for gear in build.gear:
        _upsert_item(connection, gear)
        connection.execute(
            """
            INSERT INTO build_items(build_id, item_key, act, priority, minimum_level,
                maximum_level, requirement, alternative, why)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(build_id, item_key, act) DO UPDATE SET
                priority = excluded.priority, minimum_level = excluded.minimum_level,
                maximum_level = excluded.maximum_level, requirement = excluded.requirement,
                alternative = excluded.alternative, why = excluded.why
            """,
            (
                build.id, item_key(gear.item), gear.act, gear.priority,
                gear.minimum_level, gear.maximum_level, gear.requirement,
                gear.alternative, gear.why,
            ),
        )


def _seed(connection: sqlite3.Connection) -> None:
    connection.execute(
        "DELETE FROM build_items WHERE build_id IN (SELECT build_id FROM builds WHERE origin = 'seed')"
    )
    connection.execute(
        "DELETE FROM build_levels WHERE build_id IN (SELECT build_id FROM builds WHERE origin = 'seed')"
    )
    connection.execute("DELETE FROM builds WHERE origin = 'seed'")
    for build in route_data.load_builds():
        _insert_build(connection, build, origin="seed", source_url=build.source, import_id=None)


def _migrate_custom_loadouts(connection: sqlite3.Connection) -> None:
    exists = connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'custom_loadouts'"
    ).fetchone()
    if not exists:
        return
    rows = connection.execute("SELECT payload_json FROM custom_loadouts").fetchall()
    for row in rows:
        try:
            imported = ImportedBuild.model_validate_json(row["payload_json"])
            _insert_build(connection, imported.build, origin="import",
                          source_url=imported.source_url, import_id=imported.id)
        except Exception:
            try:
                legacy = ImportedLoadout.model_validate_json(row["payload_json"])
                for character in legacy.characters:
                    _insert_build(connection, character.build, origin="import",
                                  source_url=legacy.source_url,
                                  import_id=f"{legacy.id}-{character.build.id}")
            except Exception:
                continue
    connection.execute("DROP TABLE custom_loadouts")
```

Note: `_upsert_item` uses `gear.itemKey if hasattr(...)` defensively but pydantic `BuildGear` has no `itemKey` — simplify to `item_key(gear.item)` only. (Keep the code simple; that hasattr branch must NOT survive review.)

- [ ] **Step 4: Add the `CatalogItem` model to `backend/app/models.py`** (next to `BuildGear`; used by Task 2's loaders and Task 4's endpoint)

```python
class CatalogItem(CamelModel):
    item_key: str
    name: str
    slot: str
    act: int
    region: str = ""
    acquisition: str = ""
    game_x: int | None = None
    game_y: int | None = None
    map_objective: bool = True
    effect: str = ""
    acquire: str = ""
    wiki: str = ""
    icon: str = ""
    source: str = ""
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v`
Expected: 3 PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/catalog.py backend/app/models.py backend/tests/test_catalog.py
git commit -m "feat(backend): relational catalog schema seeded from TSV exports"
```

---

### Task 2: DB-backed loaders (builds, gear, items)

**Files:**
- Modify: `backend/app/catalog.py`
- Test: `backend/tests/test_catalog.py`

- [ ] **Step 1: Write the failing tests** (append to `test_catalog.py`)

```python
def test_catalog_builds_match_tsv_seed(db_path):
    expected = {(b.id, b.name, len(b.levels), len(b.gear)) for b in tsv_builds()}
    actual = {(b.id, b.name, len(b.levels), len(b.gear)) for b in catalog.catalog_builds()}
    assert actual == expected
    sample = next(b for b in catalog.catalog_builds() if b.id == "SB-1011")
    tsv_sample = next(b for b in tsv_builds() if b.id == "SB-1011")
    assert {g.item for g in sample.gear} == {g.item for g in tsv_sample.gear}
    assert sample.target_ability_scores == tsv_sample.target_ability_scores
    assert [l.take for l in sample.levels] == [l.take for l in tsv_sample.levels]


def test_catalog_gear_merges_build_ids(db_path):
    rows = catalog.catalog_gear(act=1)
    caustic = next(row for row in rows if row.item.startswith("Caustic Band"))
    assert len(caustic.build_ids) >= 2  # shared TSV row references several builds
    assert all(row.act == 1 for row in rows)


def test_list_items_filters(db_path):
    helmets = catalog.list_items(act=1, slot="Head")
    assert helmets
    assert all(item.slot == "Head" and item.act == 1 for item in helmets)
    everything = catalog.list_items()
    assert len(everything) > len(helmets)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v -k "catalog_builds or catalog_gear or list_items"`
Expected: FAIL with `AttributeError: module 'app.catalog' has no attribute 'catalog_builds'`

- [ ] **Step 3: Implement the loaders** (append to `catalog.py`)

```python
def _gear_from_join(item_row: sqlite3.Row, join_row: sqlite3.Row, build_ids: list[str]) -> BuildGear:
    return BuildGear(
        item=item_row["name"], slot=item_row["slot"],
        priority=join_row["priority"], act=join_row["act"],
        region=item_row["region"], acquisition=item_row["acquisition"],
        why=join_row["why"], source=item_row["source"], build_ids=build_ids,
        minimum_level=join_row["minimum_level"], maximum_level=join_row["maximum_level"],
        requirement=join_row["requirement"], map_objective=bool(item_row["map_objective"]),
        alternative=join_row["alternative"], effect=item_row["effect"],
        acquire=item_row["acquire"], wiki=item_row["wiki"], icon=item_row["icon"],
        game_x=item_row["game_x"], game_y=item_row["game_y"],
    )


def catalog_builds() -> list[BuildSummary]:
    ensure_seeded()
    with _connect() as connection:
        builds = []
        for row in connection.execute(
            "SELECT * FROM builds ORDER BY origin = 'import', created_at, build_id"
        ).fetchall():
            level_rows = connection.execute(
                "SELECT * FROM build_levels WHERE build_id = ? ORDER BY level", (row["build_id"],)
            ).fetchall()
            join_rows = connection.execute(
                """
                SELECT bi.*, i.* FROM build_items bi
                JOIN items i ON i.item_key = bi.item_key
                WHERE bi.build_id = ? ORDER BY bi.id
                """,
                (row["build_id"],),
            ).fetchall()
            builds.append(BuildSummary(
                id=row["build_id"], name=row["name"], honor_status=row["honor_status"],
                role=row["role"], final_split=row["final_split"],
                class_progression=row["class_progression"],
                starting_abilities=row["starting_abilities"],
                starting_ability_scores=AbilityScores.model_validate_json(row["starting_scores_json"]) if row["starting_scores_json"] else None,
                target_ability_scores=AbilityTargetScores.model_validate_json(row["target_scores_json"]) if row["target_scores_json"] else None,
                target_ability_note=row["target_ability_note"],
                ability_setups=json.loads(row["ability_setups_json"]),
                ability_sources=json.loads(row["ability_sources_json"]),
                play_pattern=row["play_pattern"], caveat=row["caveat"],
                source=row["source_url"],
                levels=[
                    BuildLevel(
                        level=lr["level"], take=lr["take"], subclass_choice=lr["subclass_choice"],
                        choices=lr["choices"], tactics=lr["tactics"], confidence=lr["confidence"],
                        ability_score_reset=AbilityScores.model_validate_json(lr["ability_score_reset_json"]) if lr["ability_score_reset_json"] else None,
                    )
                    for lr in level_rows
                ],
                gear=[_gear_from_join(jr, jr, [row["build_id"]]) for jr in join_rows],
            ))
        return builds


def catalog_gear(act: int | None = None) -> list[BuildGear]:
    """Item-wise gear rows (one per item+act, build_ids merged) for map markers
    and the per-act equipment endpoint. Matches the legacy shared-TSV-row shape."""
    ensure_seeded()
    if act is not None and act not in (1, 2, 3):
        raise KeyError(act)
    with _connect() as connection:
        clause = "WHERE bi.act = ?" if act is not None else ""
        rows = connection.execute(
            f"""
            SELECT bi.*, i.*, GROUP_CONCAT(bi.build_id, ';') AS merged_build_ids
            FROM build_items bi JOIN items i ON i.item_key = bi.item_key
            {clause}
            GROUP BY bi.item_key, bi.act ORDER BY MIN(bi.id)
            """,
            (act,) if act is not None else (),
        ).fetchall()
        return [
            _gear_from_join(row, row, sorted(set((row["merged_build_ids"] or "").split(";"))))
            for row in rows
        ]


def list_items(act: int | None = None, slot: str | None = None) -> list[CatalogItem]:
    ensure_seeded()
    with _connect() as connection:
        clauses, params = [], []
        if act is not None:
            clauses.append("act = ?")
            params.append(act)
        if slot is not None:
            clauses.append("LOWER(slot) = LOWER(?)")
            params.append(slot)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        rows = connection.execute(
            f"SELECT * FROM items {where} ORDER BY slot, name", params
        ).fetchall()
        return [
            CatalogItem(
                item_key=row["item_key"], name=row["name"], slot=row["slot"], act=row["act"],
                region=row["region"], acquisition=row["acquisition"],
                game_x=row["game_x"], game_y=row["game_y"],
                map_objective=bool(row["map_objective"]), effect=row["effect"],
                acquire=row["acquire"], wiki=row["wiki"], icon=row["icon"], source=row["source"],
            )
            for row in rows
        ]
```

Note on `_gear_from_join(jr, jr, ...)`: the joined row exposes both tables' columns in one `sqlite3.Row`; passing it as both arguments is intentional. Column name collisions: none between the two tables except `act` and `item_key` — `build_items.act` must win, so in the JOIN SELECTs list `bi.*` **before** `i.*` and verify with the tests (sqlite keeps the first occurrence when indexing by name).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v`
Expected: 6 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/catalog.py backend/tests/test_catalog.py
git commit -m "feat(backend): DB-backed build, gear, and item loaders"
```

---

### Task 3: Relational import path + legacy migration + enrichment

**Files:**
- Modify: `backend/app/catalog.py`
- Modify: `backend/app/stores.py` (delete `RunDatabase.save_build`, `RunDatabase.load_imported_builds`, module-level `save_imported_build`, `imported_builds`)
- Test: `backend/tests/test_catalog.py`

- [ ] **Step 1: Write the failing tests** (append; reuse `sample_draft` idea from `test_loadout_import.py`)

```python
from app.loadout_import import _normalize
from tests.test_loadout_import import sample_draft


def test_save_imported_build_inserts_rows(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    catalog.ensure_seeded()
    imported = _normalize(sample_draft(), "https://example.com/swords-bard")
    catalog.save_imported_build(imported)
    builds = {b.id: b for b in catalog.catalog_builds()}
    assert imported.build.id in builds
    assert builds[imported.build.id].gear[0].item == "Titanstring Bow"
    # known item facts win over the import's sparse copy
    assert "Zhentarim" in builds[imported.build.id].gear[0].region
    listed = catalog.imported_builds()
    assert [b.id for b in listed] == [imported.id]
    assert listed[0].source_url == "https://example.com/swords-bard"


def test_import_unknown_item_upserts_and_enriches(db_path, monkeypatch):
    monkeypatch.setattr(
        catalog, "_enrich",
        lambda name: {"effect": "Test effect text", "wiki": "https://bg3.wiki/wiki/Test"},
    )
    catalog.ensure_seeded()
    draft = sample_draft()
    draft.gear[0].item = "Completely Unknown Helm"
    draft.gear[0].slot = "Head"
    imported = _normalize(draft, "https://example.com/unknown")
    catalog.save_imported_build(imported)
    item = next(i for i in catalog.list_items(slot="Head") if i.name == "Completely Unknown Helm")
    assert item.effect == "Test effect text"
    assert item.map_objective is False


def test_custom_loadouts_migration(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    imported = _normalize(sample_draft(), "https://example.com/legacy")
    # write a legacy JSON row the old way, then let ensure_seeded migrate it
    with stores.RunDatabase().connect() as connection:
        connection.execute(
            "INSERT INTO custom_loadouts(loadout_id, source_url, payload_json, updated_at) VALUES(?, ?, ?, ?)",
            (imported.id, imported.source_url, imported.model_dump_json(by_alias=True), time.time()),
        )
    catalog.ensure_seeded()
    assert [b.id for b in catalog.imported_builds()] == [imported.id]
    with sqlite3.connect(db_path) as connection:
        assert connection.execute(
            "SELECT name FROM sqlite_master WHERE name = 'custom_loadouts'"
        ).fetchone() is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v -k "imported or migration or unknown"`
Expected: FAIL with `AttributeError: ... no attribute 'save_imported_build'`

- [ ] **Step 3: Implement import save, imported_builds, and `_enrich`** (append to `catalog.py`)

```python
def _enrich(name: str) -> dict:
    """Best-effort effect/wiki lookup for items no build has described yet:
    data/item_effects.json first, then one short bg3.wiki extract call."""
    key = item_key(name)
    try:
        effects = json.loads(route_data.ITEM_EFFECTS_PATH.read_text(encoding="utf-8"))
    except Exception:
        effects = {}
    if key in effects:
        return effects[key]
    title = re.sub(r"\s*x\d+$", "", name).strip()
    try:
        query = urllib.parse.urlencode({
            "action": "query", "prop": "extracts", "explaintext": 1,
            "redirects": 1, "titles": title, "format": "json",
        })
        request = urllib.request.Request(
            f"https://bg3.wiki/w/api.php?{query}",
            headers={"User-Agent": "bg3-assistant-import/1.0"},
        )
        with urllib.request.urlopen(request, timeout=4) as response:
            data = json.loads(response.read())
        page = next(iter(data["query"]["pages"].values()))
        extract = page.get("extract", "")
        lead = extract.split("==")[0]
        first = next((p for p in lead.split("\n\n") if p.strip()), "")
        first = re.sub(r"\s+", " ", first).strip()[:240]
        if first:
            return {"effect": first, "wiki": f"https://bg3.wiki/wiki/{title.replace(' ', '_')}"}
    except Exception:
        pass
    return {}


def save_imported_build(imported: ImportedBuild) -> None:
    ensure_seeded()
    with _connect() as connection:
        known = {
            row["item_key"]
            for row in connection.execute("SELECT item_key FROM items").fetchall()
        }
        enriched_gear = []
        for gear in imported.build.gear:
            if item_key(gear.item) not in known:
                extra = _enrich(gear.item)
                gear = gear.model_copy(update={
                    "effect": extra.get("effect", gear.effect),
                    "acquire": extra.get("acquire", gear.acquire),
                    "wiki": extra.get("wiki", gear.wiki),
                })
            enriched_gear.append(gear)
        build = imported.build.model_copy(update={"gear": enriched_gear})
        # known-item facts win: skip the items upsert for keys we already have
        _insert_build_import_safe(connection, build, imported)


def _insert_build_import_safe(connection: sqlite3.Connection, build: BuildSummary, imported: ImportedBuild) -> None:
    known = {row["item_key"] for row in connection.execute("SELECT item_key FROM items").fetchall()}
    connection.execute("DELETE FROM builds WHERE build_id = ?", (build.id,))
    _insert_build_row_only(connection, build, imported)
    for gear in build.gear:
        if item_key(gear.item) not in known:
            _upsert_item(connection, gear)
        connection.execute(
            """
            INSERT INTO build_items(build_id, item_key, act, priority, minimum_level,
                maximum_level, requirement, alternative, why)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(build_id, item_key, act) DO UPDATE SET
                priority = excluded.priority, minimum_level = excluded.minimum_level,
                maximum_level = excluded.maximum_level, requirement = excluded.requirement,
                alternative = excluded.alternative, why = excluded.why
            """,
            (build.id, item_key(gear.item), gear.act, gear.priority, gear.minimum_level,
             gear.maximum_level, gear.requirement, gear.alternative, gear.why),
        )
```

Refactor note (DRY): during implementation, restructure `_insert_build` from Task 1 into `_insert_build(connection, build, origin, source_url, import_id, *, overwrite_items: bool)` so seed passes `overwrite_items=True` and import passes `False`, with `_insert_build_row_only` and the levels loop shared — do NOT keep two near-identical insert paths. The tests stay identical. Then:

```python
def imported_builds() -> list[ImportedBuild]:
    ensure_seeded()
    builds = {b.id: b for b in catalog_builds()}
    with _connect() as connection:
        rows = connection.execute(
            "SELECT build_id, import_id, name, source_url FROM builds WHERE origin = 'import' ORDER BY created_at DESC"
        ).fetchall()
    return [
        ImportedBuild(
            id=row["import_id"] or row["build_id"], name=row["name"],
            source_url=row["source_url"], build=builds[row["build_id"]],
        )
        for row in rows
    ]
```

Also update `_migrate_custom_loadouts` to route through the import-safe insert so migrated rows don't clobber seeded item facts.

- [ ] **Step 4: Delete the legacy blob path in `stores.py`**

Remove `RunDatabase.save_build`, `RunDatabase.load_imported_builds`, module-level `save_imported_build`, `imported_builds`, and the now-unused `ImportedLoadout` import. The `custom_loadouts` CREATE TABLE stays in `connect()` (harmless; migration drops the table — but leaving the DDL would recreate it on next connect, so **also remove the `custom_loadouts` CREATE TABLE from `RunDatabase.connect()`** and let `_migrate_custom_loadouts`'s existence check handle old databases).

- [ ] **Step 5: Run the full backend suite**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest -v`
Expected: test_catalog.py all PASS; `test_loadout_import.py` may FAIL where it touches `stores.save_imported_build` — update those references to `catalog.save_imported_build` / `catalog.imported_builds` as part of this task (the import flow behavior is unchanged).

- [ ] **Step 6: Commit**

```bash
git add backend/app/catalog.py backend/app/stores.py backend/tests/
git commit -m "feat(backend): imports write relational rows; migrate custom_loadouts blobs"
```

---

### Task 4: Serve from the catalog + `GET /api/items`

**Files:**
- Modify: `backend/app/main.py` (route payload, `/api/builds/custom`, import endpoint, acts equipment endpoint; add `/api/items`)
- Modify: `backend/app/map_data.py` (line ~22 imports; `load_gear`/`load_builds` call sites → `catalog.catalog_gear`/`catalog.catalog_builds`)
- Modify: `backend/app/route_data.py` (`assess_readiness` builds lookup; `load_act_catalog` equipment counts)
- Test: `backend/tests/test_catalog.py`

- [ ] **Step 1: Write the failing tests** (append)

```python
from fastapi.testclient import TestClient
from app import main


def test_items_endpoint_filters(db_path):
    client = TestClient(main.app)
    response = client.get("/api/items", params={"act": 1, "slot": "Head"})
    assert response.status_code == 200
    items = response.json()
    assert items
    assert all(item["slot"] == "Head" and item["act"] == 1 for item in items)
    assert {"item_key", "name", "effect", "icon"} <= set(items[0])


def test_route_payload_builds_come_from_catalog(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    catalog.ensure_seeded()
    imported = _normalize(sample_draft(), "https://example.com/payload")
    catalog.save_imported_build(imported)
    client = TestClient(main.app)
    payload = client.get("/api/act1/route").json()
    ids = {build["id"] for build in payload["builds"]}
    assert imported.build.id in ids
    assert any(build["id"] == "SB-1011" for build in payload["builds"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest tests/test_catalog.py -v -k "endpoint or payload"`
Expected: `/api/items` → 404 FAIL; payload test FAIL (imported build missing because main still reads dropped stores functions — likely an AttributeError at import time, which is the point).

- [ ] **Step 3: Rewire main.py**

In `backend/app/main.py`:
- Add `catalog` to the `from . import ...` line.
- `/api/act1/route`: replace the `imported_builds`/`load_builds` merge with `builds = catalog.catalog_builds()` and dump that list (keep the `{build.id: build}` dedupe if you like, but catalog ids are unique by PK — drop the dict).
- `/api/builds/custom`: `return catalog.imported_builds()`.
- `/api/builds/import`: `stores.save_imported_build(imported)` → `catalog.save_imported_build(imported)`.
- `/api/acts/{act}/equipment` (the handler returning `load_gear(act)` near line 90): `return catalog.catalog_gear(act)`.
- New endpoint (snake_case dump to match the app's `convertFromSnakeCase` decoder, same style as `/api/act1/route`):

```python
@app.get("/api/items")
def catalog_items(act: int | None = None, slot: str | None = None) -> JSONResponse:
    return JSONResponse(
        content=[item.model_dump(mode="json") for item in catalog.list_items(act=act, slot=slot)]
    )
```

In `backend/app/map_data.py`: change the import line to pull `catalog_gear` (and `catalog_builds` if `load_builds` is used) from `.catalog`, keep `item_key`/`load_act_catalog`/`load_route` from `.route_data`, and rename call sites (`load_gear()` → `catalog_gear()`, `load_gear(act)` → `catalog_gear(act)`).

In `backend/app/route_data.py`:
- `assess_readiness`: replace `builds = {build.id: build for build in load_builds()}` with a function-local `from . import catalog` + `builds = {build.id: build for build in catalog.catalog_builds()}` (function-local import avoids the catalog↔route_data cycle).
- `load_act_catalog`: `equipment_count=len(load_gear(act))` still counts TSV rows; change to a function-local catalog import and `len(catalog.catalog_gear(act))`, and drop its `lru_cache` (counts now change when imports land).

- [ ] **Step 4: Run the full backend suite**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest -v`
Expected: all PASS (fix any test that stubbed `stores.imported_builds` — point it at `catalog.imported_builds`; `tests/test_act_data.py` may compare TSV-based counts — those still pass because seed mirrors the TSVs).

- [ ] **Step 5: Commit**

```bash
git add backend/app/ backend/tests/
git commit -m "feat(backend): serve builds/gear/items from the catalog DB"
```

---

### Task 5: Swift `ItemSummary` + catalog fetch

**Files:**
- Modify: `mac/BG3Assistant/BG3Models.swift` (add `ItemSummary` near `BuildGear`)
- Modify: `mac/BG3Assistant/BackendClient.swift` (add `items()` mirroring `route()`)
- Modify: `mac/BG3Assistant/AppState.swift` (published `itemCatalog`, fetched wherever `backendClient.route()` result is applied)

- [ ] **Step 1: Add the model**

```swift
/// One catalog item served by GET /api/items — item facts only (no
/// per-build opinions). Decoded with convertFromSnakeCase like RoutePayload.
struct ItemSummary: Codable, Hashable, Identifiable {
    var id: String { itemKey }
    let itemKey: String
    let name: String
    let slot: String
    let act: Int
    var region: String = ""
    var acquisition: String = ""
    var gameX: Int? = nil
    var gameY: Int? = nil
    var mapObjective: Bool = true
    var effect: String = ""
    var acquire: String = ""
    var wiki: String = ""
    var icon: String = ""
    var source: String = ""
}
```

- [ ] **Step 2: Add the client call** (same shape as `route()`)

```swift
func items() async throws -> [ItemSummary] {
    let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "api/items"))
    try validate(response, data: data)
    return try decoder.decode([ItemSummary].self, from: data)
}
```

- [ ] **Step 3: Fetch alongside the route payload**

In `AppState.swift`, add `@Published var itemCatalog: [ItemSummary] = []` next to `builds`. Find the function that awaits `backendClient.route()` and assigns `builds`; immediately after that assignment add:

```swift
itemCatalog = (try? await backendClient.items()) ?? itemCatalog
```

(Non-fatal by design: an older bundled backend without `/api/items` leaves the catalog empty and the picker simply shows no alternatives.)

- [ ] **Step 4: Typecheck**

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add mac/BG3Assistant/BG3Models.swift mac/BG3Assistant/BackendClient.swift mac/BG3Assistant/AppState.swift
git commit -m "feat(mac): fetch the item catalog from the backend"
```

---

### Task 6: HonorRun assignment state + recency stamping

**Files:**
- Modify: `mac/BG3Assistant/BG3Models.swift` (`HonorRun` fields + migration defaults in `migrateLegacyPartySlots`)
- Modify: `mac/BG3Assistant/AppState+Party.swift` (`assignBuild`, `respec`)

- [ ] **Step 1: Add the persisted fields** (in `HonorRun`, next to `equippedByMember`; all optional so old snapshots decode)

```swift
// Deterministic gear assignment: when each member's current build was
// assigned ("first to request" recency), the player's manual item → member
// overrides, and per-slot catalog swaps replacing a build's pick.
var buildAssignedAt: [String: Date]?
var gearAssignmentOverrides: [String: String]?
var plannedSlotOverrides: [String: [String: String]]?
```

In `migrateLegacyPartySlots()`, after the `equippedByMember` default, add:

```swift
if buildAssignedAt == nil {
    // Legacy runs: every existing build assignment gets the same epoch stamp
    // so recency ties resolve alphabetically (deterministic for old runs).
    var stamps: [String: Date] = [:]
    for member in members where member.buildId != nil {
        stamps[member.id] = Date(timeIntervalSince1970: 0)
    }
    buildAssignedAt = stamps
}
if gearAssignmentOverrides == nil { gearAssignmentOverrides = [:] }
if plannedSlotOverrides == nil { plannedSlotOverrides = [:] }
```

- [ ] **Step 2: Stamp on assignment**

In `AppState+Party.swift` `assignBuild(_:to:)`, right after `copy.buildId = buildID`:

```swift
if buildID == nil {
    run.buildAssignedAt?.removeValue(forKey: member.id)
    run.plannedSlotOverrides?.removeValue(forKey: member.id)
} else if buildID != member.buildId {
    run.buildAssignedAt = run.buildAssignedAt ?? [:]
    run.buildAssignedAt?[member.id] = Date()
    run.plannedSlotOverrides?.removeValue(forKey: member.id)
}
```

In `respec(_:)`, next to `run.equippedByMember?[member.id] = nil`:

```swift
run.buildAssignedAt?.removeValue(forKey: member.id)
run.plannedSlotOverrides?.removeValue(forKey: member.id)
```

- [ ] **Step 3: Typecheck**

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add mac/BG3Assistant/BG3Models.swift mac/BG3Assistant/AppState+Party.swift
git commit -m "feat(mac): persist build-assignment recency and gear override state"
```

---

### Task 7: `GearLogic.assignments` resolver (pure + tested)

**Files:**
- Modify: `mac/BG3Assistant/GearLogic.swift`
- Test: `mac/Tests/BG3AssistantTests/GearLogicTests.swift`

- [ ] **Step 1: Write the failing tests** (append to `GearLogicTests.swift`)

```swift
// MARK: assignments

private func claim(
    _ memberId: String, build: String, at seconds: TimeInterval?, items: Set<String>
) -> GearLogic.GearClaim {
    GearLogic.GearClaim(
        memberId: memberId, memberName: memberId.capitalized, buildName: build,
        buildAssignedAt: seconds.map { Date(timeIntervalSince1970: $0) }, itemKeys: items
    )
}

func testAssignmentPrefersEarliestBuildAssignment() {
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
            claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
        ],
        overrides: [:]
    )
    XCTAssertEqual(result["caustic-band"], "astarion")
}

func testAssignmentTieBreaksAlphabeticallyByBuildName() {
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: 100, items: ["caustic-band"]),
            claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
        ],
        overrides: [:]
    )
    XCTAssertEqual(result["caustic-band"], "astarion")  // "Assassin" < "Zerker"
}

func testOverrideBeatsRecency() {
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
            claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
        ],
        overrides: ["caustic-band": "karlach"]
    )
    XCTAssertEqual(result["caustic-band"], "karlach")
}

func testStaleOverrideFallsBackToRecency() {
    // Override points at someone who no longer wants (or has) the item.
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: 200, items: ["caustic-band"]),
            claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
        ],
        overrides: ["caustic-band": "gale"]
    )
    XCTAssertEqual(result["caustic-band"], "astarion")
}

func testUncontestedItemsAssignToTheirOnlyClaimant() {
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: 200, items: ["haste-helm"]),
            claim("astarion", build: "Assassin", at: 100, items: ["caustic-band"]),
        ],
        overrides: [:]
    )
    XCTAssertEqual(result["haste-helm"], "karlach")
    XCTAssertEqual(result["caustic-band"], "astarion")
}

func testMissingAssignmentDateSortsLast() {
    let result = GearLogic.assignments(
        claims: [
            claim("karlach", build: "Zerker", at: nil, items: ["caustic-band"]),
            claim("astarion", build: "Assassin", at: 500, items: ["caustic-band"]),
        ],
        overrides: [:]
    )
    XCTAssertEqual(result["caustic-band"], "astarion")
}
```

- [ ] **Step 2: Implement the resolver** (append to `GearLogic`)

```swift
/// One active member's claim on gear: identity, tie-break names, when their
/// build was assigned, and the item keys their plan currently wants.
struct GearClaim: Equatable {
    let memberId: String
    let memberName: String
    let buildName: String
    let buildAssignedAt: Date?
    let itemKeys: Set<String>
}

/// Deterministic item → member assignment. Manual override wins when its
/// target still claims the item; otherwise the earliest build assignment
/// ("first to request"), then alphabetical build name, member name, id.
static func assignments(
    claims: [GearClaim],
    overrides: [String: String]
) -> [String: String] {
    var result: [String: String] = [:]
    let allKeys = claims.reduce(into: Set<String>()) { $0.formUnion($1.itemKeys) }
    for key in allKeys {
        let claimants = claims.filter { $0.itemKeys.contains(key) }
        if let chosen = overrides[key], claimants.contains(where: { $0.memberId == chosen }) {
            result[key] = chosen
            continue
        }
        result[key] = claimants.min { lhs, rhs in
            let lhsDate = lhs.buildAssignedAt ?? .distantFuture
            let rhsDate = rhs.buildAssignedAt ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            if lhs.buildName.lowercased() != rhs.buildName.lowercased() {
                return lhs.buildName.lowercased() < rhs.buildName.lowercased()
            }
            if lhs.memberName.lowercased() != rhs.memberName.lowercased() {
                return lhs.memberName.lowercased() < rhs.memberName.lowercased()
            }
            return lhs.memberId < rhs.memberId
        }?.memberId
    }
    return result
}
```

- [ ] **Step 3: Typecheck the package**

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -3`
Expected: `Build complete!` (the test target does not build locally — no XCTest in the CLT toolchain.)

- [ ] **Step 4: Verify the logic with the scratchpad runner**

The local toolchain cannot run XCTest (recorded in TOOLCALLING_FAILURES.md). Write a standalone assertion runner in the session scratchpad that copies the `GearClaim`/`assignments` implementation plus plain-`assert` versions of the six tests, then:

Run: `swiftc -o <scratchpad>/assignments_runner <scratchpad>/assignments_runner.swift && <scratchpad>/assignments_runner && echo ALL-PASS`
Expected: `ALL-PASS`

(The XCTest file stays in the repo for Xcode/CI machines; the runner is throwaway verification, not committed.)

- [ ] **Step 5: Commit**

```bash
git add mac/BG3Assistant/GearLogic.swift mac/Tests/BG3AssistantTests/GearLogicTests.swift
git commit -m "feat(mac): deterministic gear assignment resolver"
```

---

### Task 8: AppState planned-assignment API

**Files:**
- Modify: `mac/BG3Assistant/AppState+Party.swift` (`gearConflict`, new members)
- Modify: `mac/BG3Assistant/AppState+GearTarget.swift` (`routePickups`)

- [ ] **Step 1: Add wants, claims, and the resolver bridge** (in `AppState+Party.swift`, near `gearOwner`)

```swift
/// The member's current plan for this act: build picks filtered by act and
/// level, with any player slot swaps substituted in.
func wantedGear(for member: PartyMember) -> [BuildGear] {
    guard let buildId = member.buildId,
          let build = builds.first(where: { $0.id == buildId }) else { return [] }
    let overrides = run.plannedSlotOverrides?[member.id] ?? [:]
    var gear = build.gear.filter {
        $0.act == selectedAct && $0.isAvailable(at: member.level)
            && overrides[LoadoutSlot.classify($0.slot).id] == nil
    }
    for (slotID, itemKey) in overrides {
        guard let item = itemCatalog.first(where: { $0.itemKey == itemKey }),
              item.act <= selectedAct,
              LoadoutSlot.classify(item.slot).id == slotID else { continue }
        gear.append(syntheticGear(from: item))
    }
    return gear
}

/// A catalog item dressed as BuildGear so every existing gear surface
/// (doll grid, drawer, detail view, maps) renders player swaps unchanged.
func syntheticGear(from item: ItemSummary) -> BuildGear {
    BuildGear(
        item: item.name, slot: item.slot, priority: "Chosen", act: item.act,
        region: item.region, acquisition: item.acquisition,
        why: "Player-chosen replacement pick", source: item.wiki,
        minimumLevel: nil, maximumLevel: nil, requirement: nil,
        mapObjective: item.mapObjective, alternative: nil,
        effect: item.effect, acquire: item.acquire, wiki: item.wiki,
        icon: item.icon, gameX: item.gameX, gameY: item.gameY
    )
}

private var assignmentClaims: [GearLogic.GearClaim] {
    activeParty.compactMap { member in
        guard let buildId = member.buildId,
              let build = builds.first(where: { $0.id == buildId }) else { return nil }
        return GearLogic.GearClaim(
            memberId: member.id, memberName: member.name, buildName: build.name,
            buildAssignedAt: run.buildAssignedAt?[member.id],
            itemKeys: Set(wantedGear(for: member).map(\.itemKey))
        )
    }
}

var plannedAssignments: [String: String] {
    GearLogic.assignments(claims: assignmentClaims, overrides: run.gearAssignmentOverrides ?? [:])
}

func plannedOwner(ofItemKey key: String) -> PartyMember? {
    guard let memberId = plannedAssignments[key] else { return nil }
    return activeParty.first { $0.id == memberId }
}

func setGearAssignmentOverride(_ gear: BuildGear, to member: PartyMember) {
    run.gearAssignmentOverrides = run.gearAssignmentOverrides ?? [:]
    run.gearAssignmentOverrides?[gear.itemKey] = member.id
    persistRun()
}

func slotOverride(for member: PartyMember, slot: LoadoutSlot) -> String? {
    run.plannedSlotOverrides?[member.id]?[slot.id]
}

func setSlotOverride(_ slot: LoadoutSlot, itemKey: String?, for member: PartyMember) {
    var all = run.plannedSlotOverrides ?? [:]
    var mine = all[member.id] ?? [:]
    mine[slot.id] = itemKey
    all[member.id] = mine.isEmpty ? nil : mine
    run.plannedSlotOverrides = all
    persistRun()
}
```

- [ ] **Step 2: Re-base `gearConflict` on the resolver** (replace the priority-rank body; keep the signature and the confirmed-owner branch)

```swift
/// Cross-build claim on the same item: either the player already confirmed
/// an owner, or several active plans want it and assignment recency decides.
func gearConflict(for gear: BuildGear, member: PartyMember) -> GearConflict? {
    if let owner = gearOwner(gear), owner.id != member.id {
        return GearConflict(
            mine: false,
            short: "Equipped by \(owner.name)",
            detail: gearConflictDetail(gear, base: "\(owner.name) is the player-confirmed owner.")
        )
    }
    let key = gear.itemKey
    let rivals = activeParty.filter { other in
        other.id != member.id && wantedGear(for: other).contains { $0.itemKey == key }
    }
    guard !rivals.isEmpty, let planned = plannedOwner(ofItemKey: key) else { return nil }
    let rivalNames = rivals.map(\.name).joined(separator: ", ")
    if planned.id == member.id {
        return GearConflict(
            mine: true,
            short: "Also wanted by \(rivalNames)",
            detail: gearConflictDetail(gear, base: "\(member.name)'s build requested it first, so \(member.name) gets it. Open the item to hand it to someone else.")
        )
    }
    return GearConflict(
        mine: false,
        short: "Assigned to \(planned.name)",
        detail: gearConflictDetail(gear, base: "\(planned.name)'s build requested it first. Use “Give to \(member.name)” to override.")
    )
}
```

- [ ] **Step 3: Route pickups follow the planned owner** (in `AppState+GearTarget.swift`, `routePickups`)

Replace the per-member `wanted` filter body so each unowned item surfaces only for its planned owner, and swapped picks ride along:

```swift
var routePickups: [GearLogic.Pickup] {
    var seen = Set<String>()
    var pickups: [GearLogic.Pickup] = []
    for member in activeParty {
        let wanted = wantedGear(for: member)
            .filter {
                gearOwner($0) == nil
                    && (plannedOwner(ofItemKey: $0.itemKey)?.id ?? member.id) == member.id
            }
            .sorted { GearLogic.priorityRank($0.priority) < GearLogic.priorityRank($1.priority) }
        for gear in wanted {
            let key = "\(member.id)|\(gear.itemKey)"
            guard seen.insert(key).inserted else { continue }
            pickups.append(GearLogic.Pickup(gear: gear, memberId: member.id, memberName: member.name))
        }
    }
    return pickups
}
```

- [ ] **Step 4: Typecheck**

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add mac/BG3Assistant/AppState+Party.swift mac/BG3Assistant/AppState+GearTarget.swift
git commit -m "feat(mac): planned gear assignment drives conflicts and pickups"
```

---

### Task 9: Loadout UI — assignment display, give-to, Change pick

**Files:**
- Modify: `mac/BG3Assistant/LoadoutTabView.swift` (`availableGear`, `slotGlyph`, drawer)
- Modify: `mac/BG3Assistant/GearDetailView.swift` (actions row)

- [ ] **Step 1: Doll grid reads the plan.** In `LoadoutTabView.availableGear`, replace `build.gear.filter { ... }` with:

```swift
private var availableGear: [BuildGear] {
    guard let member else { return [] }
    return appState.wantedGear(for: member)
        .sorted { GearLogic.priorityRank($0.priority) < GearLogic.priorityRank($1.priority) }
}
```

(The `build` guard can drop; `wantedGear` handles it. `laterSection` keeps using `build.gear` — future picks are build opinions, not the current plan.)

- [ ] **Step 2: Slot glyph shows the planned owner.** In `slotGlyph`, replace the `gearOwner(first)` branch:

```swift
} else if let planned = appState.plannedOwner(ofItemKey: first.itemKey), planned.id != member.id {
    Image(systemName: "arrow.left.arrow.right.circle")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(BG3Theme.warning)
        .help("Assigned to \(planned.name) — their build requested it first")
}
```

(Keep the confirmed-equip branches above it unchanged; confirmed ownership still wins visually.)

- [ ] **Step 3: “Give to” + assignment chip in `GearDetailView`.** In `header`, extend the chip chain: after the `owner` case add

```swift
} else if let planned = appState.plannedOwner(ofItemKey: gear.itemKey), planned.id != member.id {
    StatusChip(text: "→ \(planned.name)", tint: BG3Theme.warning)
}
```

In `actions`, before the map button add:

```swift
if !equipped,
   let planned = appState.plannedOwner(ofItemKey: gear.itemKey),
   planned.id != member.id {
    Button {
        appState.setGearAssignmentOverride(gear, to: member)
    } label: {
        Label("Give to \(member.name)", systemImage: "person.fill.checkmark")
    }
    .assistantActionButton(accent: BG3Theme.warning)
    .help("Override the automatic assignment — \(planned.name)'s build requested it first")
}
```

- [ ] **Step 4: “Change pick” section in the pinned drawer.** In `LoadoutTabView.drawer`, inside the pinned branch after the `ForEach(items)` loop (and before the click-to-pin hint), add `changePickSection(slot, items: items, member: member)` guarded by `pinnedSlot != nil`, implemented as:

```swift
@ViewBuilder private func changePickSection(_ slot: LoadoutSlot, items: [BuildGear], member: PartyMember) -> some View {
    let options = appState.itemCatalog
        .filter { option in
            LoadoutSlot.classify(option.slot) == slot
                && option.act <= appState.selectedAct
                && !items.contains { $0.itemKey == option.itemKey }
        }
        .sorted { $0.name < $1.name }
    let overridden = appState.slotOverride(for: member, slot: slot) != nil
    if overridden || !options.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Change pick")
                    .font(BG3Type.overline).textCase(.uppercase)
                    .foregroundStyle(BG3Theme.gold)
                Spacer()
                if overridden {
                    Button("Revert to build pick") {
                        appState.setSlotOverride(slot, itemKey: nil, for: member)
                    }
                    .buttonStyle(.plain).font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.warning)
                    .help("Drop the swapped-in item and restore the build's own pick")
                }
            }
            ForEach(options) { option in
                HStack(alignment: .top, spacing: 6) {
                    GearItemIcon(gear: appState.syntheticGear(from: option), size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name)
                            .font(BG3Type.captionBold).foregroundStyle(BG3Theme.parchment)
                        Text(option.effect.isEmpty ? "No effect description yet — see the wiki." : option.effect)
                            .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button("Use") {
                        appState.setSlotOverride(slot, itemKey: option.itemKey, for: member)
                    }
                    .assistantActionButton(accent: BG3Theme.gold)
                }
                .help(option.effect.isEmpty ? option.name : option.effect)
            }
        }
        .padding(.top, 4)
    }
}
```

- [ ] **Step 5: Typecheck, then run the app**

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -3` → `Build complete!`
Then use the project's `verify` skill to launch the overlay with the planner on the Loadout tab and confirm: slot click shows Change pick with effect text, "Use" swaps the cell, contested items show "→ Name" and "Give to X" flips the assignment, and hover still previews details.

- [ ] **Step 6: Commit**

```bash
git add mac/BG3Assistant/LoadoutTabView.swift mac/BG3Assistant/GearDetailView.swift
git commit -m "feat(mac): slot swapping and assignment overrides in the Loadout tab"
```

---

### Task 10: End-to-end verification, bundle, docs

**Files:**
- Modify: `docs/developers/ARCHITECTURE.md` (data-layer section: TSVs are seed-only; catalog tables; assignment model)
- Modify: `TOOLCALLING_FAILURES.md` only if new failures occur

- [ ] **Step 1: Full test sweep**

Run: `cd /Users/jcarbs/Code/bg3_assistant/backend && uv run pytest -v` → all PASS
Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && swift build 2>&1 | tail -3` → `Build complete!`

- [ ] **Step 2: Rebuild the bundled app** (backend changes ship only via the PyInstaller bundle — frozen-backend supervisor)

Run: `cd /Users/jcarbs/Code/bg3_assistant/mac && ./scripts/build-app.sh`
Expected: bundle builds and signs; on first launch the backend seeds the catalog and `/api/items` responds (spot-check with `curl -s http://127.0.0.1:8787/api/items?act=1&slot=Head | python3 -m json.tool | head`).

- [ ] **Step 3: Runtime pass with the `verify` skill**

Seed an isolated state dir (`BG3_ASSISTANT_STATE_DIR`) with two members sharing a contested item; confirm the deterministic default (earlier assignment wins; equal stamps → alphabetical build), the override flow, a slot swap appearing in route pickups, and that an existing run's snapshot still loads (migration defaults).

- [ ] **Step 4: Update ARCHITECTURE.md** — document: catalog tables and seed-version guard; per-build spreadsheet tabs are no longer a source (tabs through "Inspiration on the go" only); import → relational rows + enrichment; assignment recency model and the three new `HonorRun` fields.

- [ ] **Step 5: Final commit**

```bash
git add docs/developers/ARCHITECTURE.md
git commit -m "docs: catalog DB and deterministic gear assignment"
```

---

## Self-review notes (already applied)

- **Spec coverage:** relational tables + migration (T1–T3), spreadsheet decoupling (T1 seeds from checked-in TSVs; nothing reads per-build tabs), serving + `/api/items` (T4), recency assignment + overrides (T6–T8), slot swap + hover effects (T5, T9), tests/bundle/docs (T10).
- **Known intentional simplifications (YAGNI):** no delete-build UI; item-wise `catalog_gear` takes the first join row's opinions (same as legacy shared TSV rows); `_enrich` only fills effect/wiki, not icons/coords, for unknown imports.
- **Type consistency check:** `GearClaim` fields match between Task 7 impl and Task 8 call site; `ItemSummary.itemKey` vs backend `item_key` handled by `convertFromSnakeCase`; `catalog.list_items` returns `CatalogItem` (pydantic) while Swift decodes `ItemSummary` — field sets match 1:1.
