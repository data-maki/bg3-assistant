"""/health advertises whether server-side AI features are available."""

from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.auth import companion_session
from app.models import HostedAuthResponse


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


def test_health_reports_ai_available_with_key(monkeypatch):
    payload = _health(monkeypatch, "sk-or-test-key")
    assert payload["ai_available"] is True


def test_health_reports_ai_unavailable_without_key(monkeypatch):
    payload = _health(monkeypatch, "")
    assert payload["ai_available"] is False


def test_health_reports_ai_unavailable_until_hosted_backend_authenticates(monkeypatch):
    payload = _health(monkeypatch, "", "https://assistant.example.com")
    assert payload["ai_available"] is False


def test_health_reports_quota_after_hosted_backend_authenticates(monkeypatch):
    companion_session.set(
        HostedAuthResponse(
            accessToken="hosted-token",
            expiresIn=3600,
            buildImports={"limit": 30, "used": 5, "remaining": 25},
        )
    )

    payload = _health(monkeypatch, "local-key-must-be-ignored", "https://assistant.example.com")

    assert payload["ai_available"] is True
    assert payload["authenticated"] is True
    assert payload["build_imports"] == {"limit": 30, "used": 5, "remaining": 25}
