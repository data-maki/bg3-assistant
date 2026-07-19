"""/health advertises whether server-side AI features are available."""

from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


def _health(monkeypatch, key: str, upstream: str = "") -> dict:
    monkeypatch.setenv("OPENROUTER_API_KEY", key)
    monkeypatch.setenv("BG3_UPSTREAM_BACKEND_URL", upstream)
    get_settings.cache_clear()
    try:
        with TestClient(app) as client:
            response = client.get("/health")
    finally:
        get_settings.cache_clear()
    assert response.status_code == 200
    return response.json()


def test_health_reports_ai_unavailable_without_key(monkeypatch):
    payload = _health(monkeypatch, "")
    assert payload["ai_available"] is False
