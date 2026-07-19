import sqlite3

from fastapi.testclient import TestClient

from app import catalog, main
from app.loadout_import import _normalize
from conftest import sample_draft


def table_count(path, table):
    with sqlite3.connect(path) as connection:
        return connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def test_seed_is_idempotent(db_path):
    catalog.ensure_seeded()
    first = table_count(db_path, "build_items")
    catalog.reset_for_tests()
    catalog.ensure_seeded()
    assert table_count(db_path, "build_items") == first


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


def test_route_payload_builds_come_from_catalog(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    catalog.ensure_seeded()
    imported = _normalize(sample_draft(), "https://example.com/payload")
    catalog.save_imported_build(imported)
    client = TestClient(main.app)
    payload = client.get("/api/acts/1/guide").json()
    ids = {build["id"] for build in payload["builds"]}
    assert imported.build.id in ids
    assert any(build["id"] == "SB-1011" for build in payload["builds"])
