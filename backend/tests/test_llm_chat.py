"""Hermetic tests for the OpenRouter chat layer (no real network calls)."""

from app import llm_chat
from app.config import Settings
from app.guide_chat import guide_facts
from app.models import ChatRequest
from app.route_data import checkpoint_by_id
from app.walkthrough_data import walkthrough_by_id


def _request(**fields) -> ChatRequest:
    return ChatRequest(message="What ends my run?", checkpoint_id="fight-nere", **fields)


def test_no_key_falls_back_to_deterministic_guide_chat() -> None:
    settings = Settings(OPENROUTER_API_KEY="")
    result = llm_chat.answer(checkpoint_by_id("fight-nere"), _request(), None, settings)
    assert result.guide_facts
    assert "Guide says:" in result.answer


def test_llm_answer_used_when_key_present(monkeypatch) -> None:
    captured = {}

    class FakeResponse:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": "Free Nere within one rest or he dies."}}]}

    def fake_post(url, headers, json, timeout):  # noqa: A002 - mirror httpx.post signature
        captured["json"] = json
        return FakeResponse()

    monkeypatch.setattr(llm_chat.httpx, "post", fake_post)
    settings = Settings(OPENROUTER_API_KEY="sk-test", OPENROUTER_MODEL="google/gemini-2.5-flash")
    result = llm_chat.answer(checkpoint_by_id("fight-nere"), _request(), None, settings)

    assert result.answer.startswith("Action:")
    assert "DON'T DIE:" in result.answer
    assert "Assistant explanation: Free Nere within one rest or he dies." in result.answer
    assert result.guide_facts
    assert "Free Nere within one rest or he dies." in result.assistant_suggestions
    # The current checkpoint's guide facts must be in the grounding.
    sent = captured["json"]["messages"][1]["content"]
    text = sent if isinstance(sent, str) else sent[0]["text"]
    assert "True Soul Nere" in text and "GUIDE FACTS" in text


def test_image_is_attached_as_vision_content(monkeypatch) -> None:
    captured = {}

    class FakeResponse:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": "You're at the rubble."}}]}

    monkeypatch.setattr(
        llm_chat.httpx, "post",
        lambda url, headers, json, timeout: captured.setdefault("json", json) or FakeResponse(),
    )
    settings = Settings(OPENROUTER_API_KEY="sk-test")
    llm_chat.answer(checkpoint_by_id("fight-nere"), _request(image_base64="aGVsbG8="), None, settings)

    content = captured["json"]["messages"][1]["content"]
    assert isinstance(content, list)
    assert any(part.get("type") == "image_url" for part in content)


def test_network_failure_falls_back_to_guide_chat(monkeypatch) -> None:
    def boom(*args, **kwargs):
        raise RuntimeError("network down")

    monkeypatch.setattr(llm_chat.httpx, "post", boom)
    settings = Settings(OPENROUTER_API_KEY="sk-test")
    result = llm_chat.answer(checkpoint_by_id("fight-nere"), _request(), None, settings)
    assert result.guide_facts  # deterministic fallback kicked in


def test_power_rewards_are_in_llm_grounding() -> None:
    grounding = "\n".join(
        guide_facts(checkpoint_by_id("fight-blighted-village"), walkthrough_by_id("walk-shovel-quasit"))
    )
    assert "Power rewards" in grounding
    assert "Cheeky Quasit" in grounding


def test_guide_facts_cover_legendary_action_and_failure_conditions() -> None:
    facts = guide_facts(checkpoint_by_id("fight-auntie-ethel"), None)
    assert any(line.startswith("Legendary action:") and "Wild Magic" in line for line in facts)
    assert any("Mayrina's cage burns" in line for line in facts)


def test_guide_facts_cover_reviewed_decision() -> None:
    step = walkthrough_by_id("walk-auntie-ethel")
    facts = guide_facts(checkpoint_by_id("fight-auntie-ethel"), step)
    assert any("Reviewed decision" in line and step.decision.recommended.label in line for line in facts)
