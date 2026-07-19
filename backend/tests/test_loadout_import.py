import json

import pytest
from fastapi.testclient import TestClient

from app import loadout_import, main
from app.config import Settings
from conftest import sample_draft


def test_url_import_blocks_private_and_credentialed_urls():
    with pytest.raises(loadout_import.LoadoutImportError, match="credentials"):
        loadout_import._validate_public_url("https://user:pass@example.com/build")
    with pytest.raises(loadout_import.LoadoutImportError, match="public"):
        loadout_import._validate_public_url("http://127.0.0.1:80/private")
    with pytest.raises(loadout_import.LoadoutImportError, match="standard web ports"):
        loadout_import._validate_public_url("https://example.com:8443/build")


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


def test_import_endpoint_reports_unavailable_when_openrouter_key_is_missing(monkeypatch):
    # The key is backend-held; users have no key Settings, so the error must
    # not send them looking for one.
    monkeypatch.setattr(main, "get_settings", lambda: Settings(OPENROUTER_API_KEY=""))
    response = TestClient(main.app).post("/api/builds/import", json={"url": "https://example.com/build"})
    assert response.status_code == 428
    detail = response.json()["detail"]
    assert "not available" in detail
    assert "key" not in detail.lower()
