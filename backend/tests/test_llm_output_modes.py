import json

from app import llm_chat, loadout_import
from app.config import Settings
from conftest import sample_draft


class FakeResponse:
    def __init__(self, content):
        self.content = content

    def raise_for_status(self):
        return None

    def json(self):
        return {"choices": [{"message": {"content": self.content}}]}


def test_build_import_requests_strict_json_schema(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured.update(kwargs["json"])
        return FakeResponse(json.dumps(sample_draft().model_dump(by_alias=True)))

    monkeypatch.setattr(loadout_import.httpx, "post", fake_post)

    loadout_import._extract_draft(
        "https://example.com/build",
        "A sufficiently detailed Baldur's Gate 3 build guide.",
        Settings(OPENROUTER_API_KEY="test-key"),
    )

    assert captured["response_format"]["type"] == "json_schema"
    assert captured["response_format"]["json_schema"]["strict"] is True


def test_chat_does_not_request_structured_output(monkeypatch):
    captured = {}

    def fake_post(url, **kwargs):
        captured.update(kwargs["json"])
        return FakeResponse("Use the high ground.")

    monkeypatch.setattr(llm_chat.httpx, "post", fake_post)

    message = llm_chat._completion(
        [{"role": "user", "content": "What should I do?"}],
        Settings(OPENROUTER_API_KEY="test-key"),
        allow_tools=False,
    )

    assert message["content"] == "Use the high ground."
    assert "response_format" not in captured
