import json
import sqlite3
import time

import pytest
from fastapi.testclient import TestClient

from app import catalog, main, stores
from app.loadout_import import _normalize
from app.route_data import GUIDE_VERSION, item_key, load_builds as tsv_builds, load_gear as tsv_gear
from test_loadout_import import sample_draft


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
    assert table_count(db_path, "build_levels") == len(
        {(b.id, level.level) for b in tsv_builds() for level in b.levels}
    )
    assert table_count(db_path, "build_items") == len(
        {(b.id, item_key(g.item), g.act) for b in tsv_builds() for g in b.gear}
    )
    assert table_count(db_path, "items") == len({item_key(g.item) for g in tsv_gear()})


def test_seed_is_idempotent(db_path):
    catalog.ensure_seeded()
    first = table_count(db_path, "build_items")
    catalog.reset_for_tests()
    catalog.ensure_seeded()
    assert table_count(db_path, "build_items") == first


def test_catalog_builds_match_tsv_seed(db_path):
    expected = {(b.id, b.name, len(b.levels), len(b.gear)) for b in tsv_builds()}
    actual = {(b.id, b.name, len(b.levels), len(b.gear)) for b in catalog.catalog_builds()}
    assert actual == expected
    sample = next(b for b in catalog.catalog_builds() if b.id == "SB-1011")
    tsv_sample = next(b for b in tsv_builds() if b.id == "SB-1011")
    assert {g.item for g in sample.gear} == {g.item for g in tsv_sample.gear}
    assert sample.target_ability_scores == tsv_sample.target_ability_scores
    assert [level.take for level in sample.levels] == [level.take for level in tsv_sample.levels]


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


def test_custom_loadouts_migration(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    imported = _normalize(sample_draft(), "https://example.com/legacy")
    # write a legacy JSON row the old way, then let ensure_seeded migrate it
    with stores.RunDatabase().connect() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS custom_loadouts(
                loadout_id TEXT PRIMARY KEY,
                source_url TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
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
