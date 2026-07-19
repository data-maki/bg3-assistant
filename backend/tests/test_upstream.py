import httpx
import pytest

from app import main, upstream
from app.config import Settings
from app.models import ChatRequest, ChatResponse, HostedAuthResponse, LoadoutImportRequest
from app.route_data import load_route


def test_import_proxy_requests_stateless_processing(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured.update({"url": url, **kwargs})
        return httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={
                "id": "import-test",
                "name": "Test",
                "sourceUrl": "https://example.com/build",
                "build": {
                    "id": "import-test",
                    "name": "Test",
                    "honorStatus": "Imported",
                    "role": "Damage",
                    "finalSplit": "Fighter 12",
                    "classProgression": "Fighter 1-12",
                    "startingAbilities": "",
                    "startingAbilityScores": {
                        "strength": 17,
                        "dexterity": 14,
                        "constitution": 16,
                        "intelligence": 8,
                        "wisdom": 10,
                        "charisma": 8,
                    },
                    "playPattern": "Attack",
                    "caveat": "",
                    "source": "https://example.com/build",
                    "levels": [],
                    "gear": [],
                },
            },
        )

    monkeypatch.setattr(upstream.httpx, "post", fake_post)

    operation_id = "8a3bb450-0e51-4d60-9bf7-5bdb1052f7c0"
    result = upstream.import_build(
        "https://assistant.example.com",
        LoadoutImportRequest(url="https://example.com/build", persist=True),
        "hosted-token",
        operation_id,
    )

    assert result.imported.id == "import-test"
    assert captured["url"] == "https://assistant.example.com/v1/builds/import"
    assert captured["json"] == {"url": "https://example.com/build", "persist": False}
    assert captured["headers"] == {
        "Authorization": "Bearer hosted-token",
        "Idempotency-Key": operation_id,
    }
    assert captured["follow_redirects"] is False


def test_chat_uses_hosted_backend_instead_of_local_provider(monkeypatch):
    checkpoint = load_route()[0]
    request = ChatRequest(message="What next?", checkpoint_id=checkpoint.id)
    expected = ChatResponse(answer="Hosted answer")
    calls = []
    monkeypatch.setattr(
        main,
        "get_settings",
        lambda: Settings(
            BG3_UPSTREAM_BACKEND_URL="https://assistant.example.com",
            BG3_COMPANION_CONTROL_TOKEN="companion-control",
            OPENROUTER_API_KEY="must-not-be-used-locally",
        ),
    )
    monkeypatch.setattr(
        main.upstream,
        "chat",
        lambda base_url, body, token: calls.append((base_url, body.message, token)) or expected,
    )
    monkeypatch.setattr(
        main.llm_chat,
        "answer",
        lambda *args: (_ for _ in ()).throw(AssertionError("local provider path was used")),
    )

    main.companion_session.set(
        HostedAuthResponse(
            accessToken="hosted-token",
            expiresIn=3600,
            buildImports={"limit": 30, "used": 0, "remaining": 30},
        )
    )
    response = main.chat(request, "companion-control")

    assert response == expected
    assert calls == [("https://assistant.example.com", "What next?", "hosted-token")]


def test_chat_upstream_failure_falls_back_without_local_provider_key(monkeypatch):
    checkpoint = load_route()[0]
    request = ChatRequest(message="What next?", checkpoint_id=checkpoint.id)
    observed_keys = []
    expected = ChatResponse(answer="Guide fallback")
    monkeypatch.setattr(
        main,
        "get_settings",
        lambda: Settings(
            BG3_UPSTREAM_BACKEND_URL="https://assistant.example.com",
            BG3_COMPANION_CONTROL_TOKEN="companion-control",
            OPENROUTER_API_KEY="must-not-be-used-locally",
        ),
    )
    monkeypatch.setattr(
        main.upstream,
        "chat",
        lambda *args: (_ for _ in ()).throw(upstream.UpstreamBackendError(502, "offline")),
    )
    monkeypatch.setattr(
        main.llm_chat,
        "answer",
        lambda checkpoint, body, step, settings: observed_keys.append(settings.openrouter_api_key) or expected,
    )

    main.companion_session.set(
        HostedAuthResponse(
            accessToken="hosted-token",
            expiresIn=3600,
            buildImports={"limit": 30, "used": 0, "remaining": 30},
        )
    )
    response = main.chat(request, "companion-control")

    assert response == expected
    assert observed_keys == [""]


def test_invalid_upstream_response_is_reported_as_a_gateway_failure(monkeypatch):
    monkeypatch.setattr(
        upstream.httpx,
        "post",
        lambda url, **kwargs: httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={"unexpected": "payload"},
        ),
    )

    with pytest.raises(upstream.UpstreamBackendError) as error:
        upstream.chat(
            "https://assistant.example.com", ChatRequest(message="What next?"), "hosted-token"
        )

    assert error.value.status_code == 502
    assert "invalid response" in error.value.detail


def test_upstream_error_preserves_authoritative_quota(monkeypatch):
    monkeypatch.setattr(
        upstream.httpx,
        "post",
        lambda url, **kwargs: httpx.Response(
            403,
            request=httpx.Request("POST", url),
            headers={
                "X-Quota-Limit": "30",
                "X-Quota-Used": "30",
                "X-Quota-Remaining": "0",
            },
            json={"detail": "The lifetime limit has been reached."},
        ),
    )

    with pytest.raises(upstream.UpstreamBackendError) as error:
        upstream.import_build(
            "https://assistant.example.com",
            LoadoutImportRequest(url="https://example.com/build"),
            "hosted-token",
            "8a3bb450-0e51-4d60-9bf7-5bdb1052f7c0",
        )

    assert error.value.quota is not None
    assert error.value.quota.remaining == 0
