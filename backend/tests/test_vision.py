import io
import json

import pytest
from PIL import Image

from app import vision
from app.config import Settings
from app.route_data import load_route
from app.walkthrough_data import load_walkthrough


def _jpeg() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (64, 48), (40, 60, 30)).save(output, format="JPEG")
    return output.getvalue()


def test_visual_memory_requires_an_explicit_vision_provider() -> None:
    with pytest.raises(RuntimeError, match="OPENROUTER_API_KEY or OPENAI_API_KEY"):
        vision.analyze_screenshot(
            _jpeg(), "image/jpeg", "{}", Settings(OPENROUTER_API_KEY="", OPENAI_API_KEY=""),
            load_route(), load_walkthrough(),
        )


def test_openrouter_visual_memory_returns_completion_evidence(monkeypatch) -> None:
    captured = {}
    payload = {
        "screen_summary": "Quest completion banner after the harpy fight.",
        "detected": {
            "game": "Baldur's Gate 3",
            "likely_area": "Secluded Cove",
            "screen_kind": "exploration",
            "visible_enemies": [],
            "visible_party": ["Tav"],
            "visible_levels": [4],
            "dialogue_or_warning": "Quest complete",
            "evidence": ["Quest completion banner is visible"],
        },
        "candidates": [{
            "checkpoint_id": "fight-harpies",
            "confidence": 0.93,
            "reason": "The Secluded Cove and harpy quest result are visible.",
        }],
        "completion_candidates": [{
            "step_id": "walk-harpies",
            "confidence": 0.92,
            "reason": "The frame directly shows the reviewed quest completion result.",
        }],
        "confidence": 0.93,
    }

    class FakeResponse:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": json.dumps(payload)}}]}

    def fake_post(url, headers, json, timeout):  # noqa: A002 - mirror httpx.post
        captured["request"] = json
        return FakeResponse()

    monkeypatch.setattr(vision.httpx, "post", fake_post)
    result = vision.analyze_screenshot(
        _jpeg(), "image/jpeg", '{"checkpoint_id":"fight-harpies"}',
        Settings(OPENROUTER_API_KEY="sk-test", OPENAI_API_KEY=""), load_route(), load_walkthrough(),
    )

    assert result.completion_candidates[0].step_id == "walk-harpies"
    assert result.completion_candidates[0].confidence == 0.92
    sent = captured["request"]
    assert sent["response_format"]["type"] == "json_schema"
    prompt = sent["messages"][0]["content"][0]["text"]
    assert "Location, absence of enemies" in prompt
    assert "walk-harpies" in prompt
