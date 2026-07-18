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
    item_label TEXT NOT NULL DEFAULT '',
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

# Path of the database whose schema/seed this process has already ensured.
# Keyed on the path so tests pointing at fresh temp databases reseed them.
_seeded_path = None


def reset_for_tests() -> None:
    global _seeded_path
    _seeded_path = None


def _connect() -> sqlite3.Connection:
    """Cheap per-call connection; ensure_seeded owns schema creation/migration."""
    connection = stores.RunDatabase().connect()
    connection.row_factory = sqlite3.Row
    return connection


def _migrate_schema(connection: sqlite3.Connection) -> None:
    """Add catalog columns introduced after the first relational release."""
    additions = {
        "builds": {
            "target_ability_note": "TEXT NOT NULL DEFAULT ''",
            "ability_setups_json": "TEXT NOT NULL DEFAULT '[]'",
            "ability_sources_json": "TEXT NOT NULL DEFAULT '[]'",
        },
        "build_items": {
            "item_label": "TEXT NOT NULL DEFAULT ''",
        },
    }
    for table, columns in additions.items():
        existing = {row["name"] for row in connection.execute(f"PRAGMA table_info({table})").fetchall()}
        for name, definition in columns.items():
            if name not in existing:
                connection.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")


def ensure_seeded() -> None:
    global _seeded_path
    path = stores.RunDatabase().path
    if _seeded_path == path:
        return
    with _connect() as connection:
        connection.executescript(SCHEMA)
        _migrate_schema(connection)
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
    _seeded_path = path


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
            INSERT INTO build_items(build_id, item_key, item_label, act, priority, minimum_level,
                maximum_level, requirement, alternative, why)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(build_id, item_key, act) DO UPDATE SET
                item_label = excluded.item_label,
                priority = excluded.priority, minimum_level = excluded.minimum_level,
                maximum_level = excluded.maximum_level, requirement = excluded.requirement,
                alternative = excluded.alternative, why = excluded.why
            """,
            (
                build.id, item_key(gear.item), gear.item, gear.act, gear.priority,
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


def _gear_from_join(row: sqlite3.Row, build_ids: list[str]) -> BuildGear:
    """Build one BuildGear from a build_items × items joined row.

    The SELECT must list bi.* before i.* — on duplicate column names
    (act, item_key) sqlite3.Row keeps the first occurrence, and the
    join row's act (the build's opinion) is the one that matters.
    """
    return BuildGear(
        item=row["item_label"] or row["name"], slot=row["slot"],
        priority=row["priority"], act=row["act"],
        region=row["region"], acquisition=row["acquisition"],
        why=row["why"], source=row["source"], build_ids=build_ids,
        minimum_level=row["minimum_level"], maximum_level=row["maximum_level"],
        requirement=row["requirement"], map_objective=bool(row["map_objective"]),
        alternative=row["alternative"], effect=row["effect"],
        acquire=row["acquire"], wiki=row["wiki"], icon=row["icon"],
        game_x=row["game_x"], game_y=row["game_y"],
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
                gear=[_gear_from_join(jr, [row["build_id"]]) for jr in join_rows],
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
            _gear_from_join(row, sorted(set((row["merged_build_ids"] or "").split(";"))))
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
        _insert_build(
            connection, build, origin="import", source_url=imported.source_url,
            import_id=imported.id, overwrite_items=False,
        )


def imported_builds() -> list[ImportedBuild]:
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
