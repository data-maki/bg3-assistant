import json
import sqlite3
import time

import pytest

from app import catalog, stores
from app.route_data import GUIDE_VERSION, item_key, load_builds as tsv_builds, load_gear as tsv_gear


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
