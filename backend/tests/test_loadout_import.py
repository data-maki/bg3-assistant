import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import catalog, loadout_import, main, stores
from app.config import Settings
from app.models import ImportedBuild, ImportedBuildDraft
from conftest import sample_draft


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


def test_html_extraction_keeps_embedded_build_json():
    html = b"""
    <html><body><main>Interactive build planner</main>
    <script id="__NEXT_DATA__" type="application/json">
    {"build":{"name":"Swords Bard","levels":[{"level":1,"class":"Bard"}],"gear":["Titanstring Bow"]}}
    </script></body></html>
    """
    text = loadout_import._source_text(html, "text/html")
    assert "Swords Bard" in text
    assert "Titanstring Bow" in text


def test_normalized_import_produces_reusable_build_contract():
    imported = loadout_import._normalize(sample_draft(), "https://example.com/build")
    assert imported.id.startswith("import-")
    assert imported.build.id.startswith(imported.id)
    assert imported.build.source == "https://example.com/build"
    assert imported.build.starting_ability_scores.charisma == 17
    assert imported.build.gear[0].build_ids == [imported.build.id]
    assert imported.build.gear[0].map_objective is False
    assert imported.build.ability_setups[0].point_buy_scores.charisma == 15
    assert imported.build.ability_setups[0].bonus_two == "charisma"
    assert not hasattr(imported, "characters")


def test_import_rejects_impossible_starting_ability_allocation(monkeypatch):
    """An LLM response with illegal starting scores yields the targeted 422, not a generic 502."""
    payload = sample_draft().model_dump(by_alias=True)
    payload["startingAbilityScores"] = {
        "strength": 20, "dexterity": 20, "constitution": 20,
        "intelligence": 20, "wisdom": 20, "charisma": 20,
    }

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"choices": [{"message": {"content": json.dumps(payload)}}]}

    page = b"<html><body>" + b"A sufficiently detailed public BG3 build page. " * 4 + b"</body></html>"
    monkeypatch.setattr(main, "get_settings", lambda: Settings(OPENROUTER_API_KEY="test-key"))
    monkeypatch.setattr(loadout_import, "_download", lambda url: ("https://example.com/build", page, "text/html"))
    monkeypatch.setattr(loadout_import.httpx, "post", lambda url, **kwargs: FakeResponse())
    response = TestClient(main.app).post("/api/builds/import", json={"url": "https://example.com/build"})
    assert response.status_code == 422
    assert "not a legal BG3 27-point allocation" in response.json()["detail"]


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


def test_import_endpoint_reports_unavailable_when_openrouter_key_is_missing(monkeypatch):
    # The key is backend-held; users have no key Settings, so the error must
    # not send them looking for one.
    monkeypatch.setattr(main, "get_settings", lambda: Settings(OPENROUTER_API_KEY=""))
    response = TestClient(main.app).post("/api/builds/import", json={"url": "https://example.com/build"})
    assert response.status_code == 428
    detail = response.json()["detail"]
    assert "not available" in detail
    assert "key" not in detail.lower()


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


def test_gemini_request_uses_configured_model_and_strict_json_schema(monkeypatch):
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
    assert Settings(OPENROUTER_API_KEY="test-key").openrouter_model == "google/gemini-3-flash-preview"
    actual = loadout_import._extract_draft(
        "https://example.com/build",
        "A sufficiently detailed public BG3 build page with levels, starting abilities, choices, tactics, and equipment.",
        Settings(OPENROUTER_API_KEY="test-key", OPENROUTER_MODEL="test/import-model"),
    )
    assert actual.name == "Swords Bard"
    assert captured["json"]["model"] == "test/import-model"
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
