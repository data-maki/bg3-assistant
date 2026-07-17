from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import catalog, loadout_import, main, map_data, stores
from app.config import Settings
from app.models import ImportedBuild, ImportedBuildDraft


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
            "intelligence": 10,
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


def test_url_import_blocks_private_and_credentialed_urls(monkeypatch):
    with pytest.raises(loadout_import.LoadoutImportError, match="credentials"):
        loadout_import._validate_public_url("https://user:pass@example.com/build")
    with pytest.raises(loadout_import.LoadoutImportError, match="public"):
        loadout_import._validate_public_url("http://127.0.0.1:80/private")
    with pytest.raises(loadout_import.LoadoutImportError, match="standard web ports"):
        loadout_import._validate_public_url("https://example.com:8443/build")


def test_html_extraction_removes_executable_content():
    html = b"""
    <html><head><title>Swords Bard</title><script>SECRET_SCRIPT</script></head>
    <body><h1>Swords Bard</h1><p>College of Swords with Titanstring Bow. Take Bard at each level,
    choose Slashing Flourish, and use this character as the party face and ranged striker.</p></body></html>
    """
    text = loadout_import._source_text(html, "text/html")
    assert "Swords Bard" in text
    assert "Titanstring Bow" in text
    assert "SECRET_SCRIPT" not in text


def test_normalized_import_produces_reusable_build_contract():
    imported = loadout_import._normalize(sample_draft(), "https://example.com/build")
    assert imported.id.startswith("import-")
    assert imported.build.id.startswith(imported.id)
    assert imported.build.source == "https://example.com/build"
    assert imported.build.starting_ability_scores.charisma == 17
    assert imported.build.gear[0].build_ids == [imported.build.id]
    assert imported.build.gear[0].map_objective is False
    assert not hasattr(imported, "characters")


def test_custom_build_database_round_trip(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        stores.RunDatabase, "path", property(lambda self: tmp_path / "state.sqlite3")
    )
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    catalog.reset_for_tests()
    try:
        expected = loadout_import._normalize(sample_draft(), "https://example.com/build")
        catalog.save_imported_build(expected)
        actual = catalog.imported_builds()
        assert isinstance(actual[0], ImportedBuild)
        assert actual[0].id == expected.id
        assert actual[0].source_url == expected.source_url
        assert actual[0].build.id == expected.build.id
        assert [level.take for level in actual[0].build.levels] == [
            level.take for level in expected.build.levels
        ]
        # Gear comes back keyed to the same items, with reviewed catalog
        # facts (region, coordinates, effects) winning over the import's copy.
        assert [g.item for g in actual[0].build.gear] == [g.item for g in expected.build.gear]
        assert actual[0].build.gear[0].build_ids == [expected.build.id]
    finally:
        catalog.reset_for_tests()


def test_structured_output_schema_rejects_unknown_fields():
    schema = ImportedBuildDraft.model_json_schema()
    assert schema["additionalProperties"] is False
    assert schema["$defs"]["AbilityScores"]["additionalProperties"] is False


def test_import_endpoint_nudges_when_openrouter_key_is_missing(monkeypatch):
    monkeypatch.setattr(main, "get_settings", lambda: Settings(OPENROUTER_API_KEY=""))
    response = TestClient(main.app).post("/api/builds/import", json={"url": "https://example.com/build"})
    assert response.status_code == 428
    assert "Settings" in response.json()["detail"]


def test_import_endpoint_saves_validated_build(monkeypatch):
    imported = loadout_import._normalize(sample_draft(), "https://example.com/build")
    saved = []
    monkeypatch.setattr(main, "get_settings", lambda: Settings(OPENROUTER_API_KEY="test-key"))
    monkeypatch.setattr(main.loadout_import, "import_build", lambda url, settings: imported)
    monkeypatch.setattr(main.catalog, "save_imported_build", saved.append)
    response = TestClient(main.app).post("/api/builds/import", json={"url": "https://example.com/build"})
    assert response.status_code == 200
    assert response.json()["build"]["id"].startswith(imported.id)
    assert saved == [imported]


def test_gemini_request_uses_flash_3_and_strict_json_schema(monkeypatch):
    captured = {}

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"choices": [{"message": {"content": sample_draft().model_dump_json(by_alias=True)}}]}

    def fake_post(url, **kwargs):
        captured.update({"url": url, **kwargs})
        return FakeResponse()

    monkeypatch.setattr(loadout_import.httpx, "post", fake_post)
    actual = loadout_import._extract_draft(
        "https://example.com/build",
        "A sufficiently detailed public BG3 build page with levels, starting abilities, choices, tactics, and equipment.",
        Settings(OPENROUTER_API_KEY="test-key"),
    )
    assert actual.name == "Swords Bard"
    assert captured["json"]["model"] == "google/gemini-3-flash-preview"
    assert captured["json"]["response_format"]["type"] == "json_schema"
    assert captured["json"]["response_format"]["json_schema"]["strict"] is True
    assert captured["headers"]["Authorization"] == "Bearer test-key"


def test_imported_builds_are_available_to_native_and_map_clients(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        stores.RunDatabase, "path", property(lambda self: tmp_path / "state.sqlite3")
    )
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    catalog.reset_for_tests()
    try:
        imported = loadout_import._normalize(sample_draft(), "https://example.com/build")
        catalog.save_imported_build(imported)
        client = TestClient(main.app)
        native = client.get("/api/act1/route").json()
        web_map = client.get("/api/act1/markers").json()
        build_id = imported.build.id
        assert build_id in {build["id"] for build in native["builds"]}
        assert build_id in {build["id"] for build in web_map["builds"]}
    finally:
        catalog.reset_for_tests()
