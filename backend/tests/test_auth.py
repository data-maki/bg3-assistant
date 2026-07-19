import jwt
import pytest
import uuid
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import loadout_import, main
from app.auth import HostedAuthService, HostedAuthenticationError
from app.config import Settings
from app.models import HostedAuthResponse
from app.usage import UsageStore
from conftest import sample_draft


class FakeAppTransactionVerifier:
    def __init__(self, app_transaction_id: str = "apple-user-123"):
        self.app_transaction_id = app_transaction_id

    def verify(self, signed_app_transaction: str) -> str:
        assert signed_app_transaction == "signed-transaction"
        return self.app_transaction_id


def auth_settings(tmp_path, **overrides) -> Settings:
    values = {
        "BG3_BACKEND_MODE": "hosted",
        "OPENROUTER_API_KEY": "server-only-key",
        "BG3_AUTH_TOKEN_SECRET": "token-secret-" + "a" * 32,
        "BG3_SUBJECT_HMAC_SECRET": "subject-secret-" + "b" * 32,
        "BG3_USAGE_DB_PATH": tmp_path / "usage.sqlite3",
        "BG3_AUTH_TOKEN_TTL_SECONDS": 3600,
        **overrides,
    }
    return Settings(**values)


def test_app_transaction_exchange_issues_scoped_token_without_raw_apple_id(tmp_path):
    settings = auth_settings(tmp_path)
    service = HostedAuthService(
        settings,
        UsageStore(settings.usage_database_path, 30),
        app_transaction_verifier=FakeAppTransactionVerifier(),
    )

    response = service.exchange("signed-transaction")
    payload = jwt.decode(
        response.access_token,
        settings.auth_token_secret,
        algorithms=["HS256"],
        audience=service.audience,
        issuer=service.issuer,
    )

    assert payload["sub"] != "apple-user-123"
    assert "apple-user-123" not in response.access_token
    assert payload["scope"] == ["chat", "build-import"]
    assert response.build_imports.remaining == 30
    assert service.authenticate(f"Bearer {response.access_token}", "build-import") == payload["sub"]
    forged = jwt.encode(
        payload,
        "another-secret-that-is-at-least-thirty-two-bytes",
        algorithm="HS256",
    )
    with pytest.raises(HostedAuthenticationError, match="invalid or expired"):
        service.authenticate(f"Bearer {forged}", "build-import")

    production_settings = auth_settings(
        tmp_path,
        BG3_APPSTORE_ENVIRONMENT="Production",
        BG3_APPSTORE_APPLE_ID=123456789,
    )
    production_service = HostedAuthService(
        production_settings,
        UsageStore(tmp_path / "production.sqlite3", 30),
        app_transaction_verifier=FakeAppTransactionVerifier(),
    )
    with pytest.raises(HostedAuthenticationError, match="another app environment"):
        production_service.authenticate(f"Bearer {response.access_token}", "build-import")


def test_upstream_backend_requires_secure_origin():
    for value in [
        "http://assistant.example.com",
        "https://user:secret@assistant.example.com",
        "https://assistant.example.com/path",
        "https://127.0.0.1",
    ]:
        with pytest.raises(ValidationError):
            Settings(BG3_UPSTREAM_BACKEND_URL=value)


def test_companion_exchange_requires_ephemeral_control_token_and_redacts_bearer(monkeypatch):
    settings = Settings(
        BG3_UPSTREAM_BACKEND_URL="https://assistant.example.com",
        BG3_COMPANION_CONTROL_TOKEN="companion-control",
    )
    monkeypatch.setattr(main, "get_settings", lambda: settings)
    monkeypatch.setattr(
        main.upstream,
        "authenticate",
        lambda base_url, signed: HostedAuthResponse(
            accessToken="hosted-secret-token",
            expiresIn=3600,
            buildImports={"limit": 30, "used": 4, "remaining": 26},
        ),
    )
    client = TestClient(main.app)
    body = {"signedAppTransaction": "x" * 100}

    assert client.put("/_companion/session", json=body).status_code == 404
    response = client.put(
        "/_companion/session",
        json=body,
        headers={"X-BG3-Companion-Control": "companion-control"},
    )

    assert response.status_code == 200
    assert response.json()["authenticated"] is True
    assert response.json()["buildImports"]["remaining"] == 26
    assert "accessToken" not in response.json()
    assert "hosted-secret-token" not in response.text


def test_backend_modes_hide_the_other_process_routes(monkeypatch):
    client = TestClient(main.app)
    monkeypatch.setattr(main, "get_settings", lambda: Settings(BG3_BACKEND_MODE="hosted"))
    assert client.get("/api/items").status_code == 404
    assert client.get("/map").status_code == 404

    monkeypatch.setattr(main, "get_settings", lambda: Settings(BG3_BACKEND_MODE="local"))
    assert client.post(
        "/v1/auth/app-transaction", json={"signedAppTransaction": "x" * 100}
    ).status_code == 404


def test_hosted_import_requires_bearer_and_enforces_thirty_attempt_lifetime_quota(
    tmp_path, monkeypatch
):
    settings = Settings(
        BG3_BACKEND_MODE="hosted",
        OPENROUTER_API_KEY="server-only-key",
        BG3_BUILD_IMPORT_LIFETIME_LIMIT=30,
    )
    usage = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30)
    imported = loadout_import._normalize(sample_draft(), "https://example.com/build")
    provider_calls = []

    class FakeHostedAuth:
        def authenticate(self, authorization, required_scope):
            if authorization != "Bearer hosted-token":
                raise HostedAuthenticationError("A bearer token is required.")
            assert required_scope == "build-import"
            return "private-subject"

    monkeypatch.setattr(main, "get_settings", lambda: settings)
    monkeypatch.setattr(main, "get_hosted_auth_service", lambda: FakeHostedAuth())
    monkeypatch.setattr(main, "get_usage_store", lambda: usage)
    monkeypatch.setattr(
        main,
        "_process_build_import",
        lambda url, current_settings: provider_calls.append(url) or imported,
    )
    client = TestClient(main.app)
    body = {"url": "https://example.com/build"}

    assert client.post("/v1/builds/import", json=body).status_code == 401
    keys = [str(uuid.uuid4()) for _ in range(31)]
    for index in range(30):
        response = client.post(
            "/v1/builds/import",
            json=body,
            headers={
                "Authorization": "Bearer hosted-token",
                "Idempotency-Key": keys[index],
            },
        )
        assert response.status_code == 200
        assert response.headers["X-Quota-Used"] == str(index + 1)

    exhausted = client.post(
        "/v1/builds/import",
        json=body,
        headers={"Authorization": "Bearer hosted-token", "Idempotency-Key": keys[30]},
    )
    assert exhausted.status_code == 403
    assert exhausted.headers["X-Quota-Remaining"] == "0"
    assert len(provider_calls) == 30

    replay = client.post(
        "/v1/builds/import",
        json=body,
        headers={"Authorization": "Bearer hosted-token", "Idempotency-Key": keys[0]},
    )
    assert replay.status_code == 200
    assert replay.headers["Idempotency-Replayed"] == "true"
    assert len(provider_calls) == 30


def test_failed_import_is_charged_once_and_replays_with_current_quota(tmp_path, monkeypatch):
    settings = Settings(
        BG3_BACKEND_MODE="hosted",
        OPENROUTER_API_KEY="server-only-key",
    )
    usage = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30)
    calls = []

    class FakeHostedAuth:
        def authenticate(self, authorization, required_scope):
            return "private-subject"

    def fail_import(url, current_settings):
        calls.append(url)
        raise HTTPException(status_code=422, detail="Invalid build page.")

    monkeypatch.setattr(main, "get_settings", lambda: settings)
    monkeypatch.setattr(main, "get_hosted_auth_service", lambda: FakeHostedAuth())
    monkeypatch.setattr(main, "get_usage_store", lambda: usage)
    monkeypatch.setattr(main, "_process_build_import", fail_import)
    client = TestClient(main.app)
    headers = {
        "Authorization": "Bearer hosted-token",
        "Idempotency-Key": "8a3bb450-0e51-4d60-9bf7-5bdb1052f7c0",
    }

    first = client.post("/v1/builds/import", json={"url": "https://example.com/build"}, headers=headers)
    replay = client.post("/v1/builds/import", json={"url": "https://example.com/build"}, headers=headers)

    assert first.status_code == 422
    assert replay.status_code == 422
    assert first.headers["X-Quota-Used"] == "1"
    assert replay.headers["X-Quota-Remaining"] == "29"
    assert calls == ["https://example.com/build"]
