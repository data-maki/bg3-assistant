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
            item_key(gear.item),
            re.sub(r"\s*x\d+$", "", gear.item).strip() or gear.item,
            gear.slot, gear.act, gear.region, gear.acquisition,
            gear.game_x, gear.game_y, int(gear.map_objective),
            gear.effect, gear.acquire, gear.wiki, gear.icon, gear.source, time.time(),
        ),
    )


def _insert_build(
    connection: sqlite3.Connection,
    build: BuildSummary,
    origin: str,
    source_url: str,
    import_id: str | None,
    *,
    overwrite_items: bool,
) -> None:
    """Insert (or replace) one build with its levels and item joins.

    `overwrite_items=True` refreshes item facts from the build's gear rows
    (seeding from the reviewed TSVs); `False` only inserts items the catalog
    has never seen, so an import's sparse copy cannot clobber reviewed facts.
    """
    known = {
        row["item_key"]
        for row in connection.execute("SELECT item_key FROM items").fetchall()
    }
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
        if overwrite_items or item_key(gear.item) not in known:
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
        _insert_build(
            connection, build, origin="seed", source_url=build.source,
            import_id=None, overwrite_items=True,
        )


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
            _insert_build(
                connection, imported.build, origin="import",
                source_url=imported.source_url, import_id=imported.id,
                overwrite_items=False,
            )
        except Exception:
            try:
                legacy = ImportedLoadout.model_validate_json(row["payload_json"])
                for character in legacy.characters:
                    _insert_build(
                        connection, character.build, origin="import",
                        source_url=legacy.source_url,
                        import_id=f"{legacy.id}-{character.build.id}",
                        overwrite_items=False,
                    )
            except Exception:
                continue
    connection.execute("DROP TABLE custom_loadouts")
