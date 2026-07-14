import base64
import io
import json

import httpx
from openai import OpenAI
from PIL import Image

from .config import Settings
from .models import RouteCheckpoint, ScreenCandidate, ScreenDetected, VisualCompletionCandidate, VisionResult, WalkthroughStep


OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


VISION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["screen_summary", "detected", "candidates", "completion_candidates", "confidence"],
    "properties": {
        "screen_summary": {"type": "string"},
        "detected": {
            "type": "object",
            "additionalProperties": False,
            "required": ["game", "likely_area", "screen_kind", "visible_enemies", "visible_party", "visible_levels", "dialogue_or_warning", "evidence"],
            "properties": {
                "game": {"type": "string"},
                "likely_area": {"type": "string"},
                "screen_kind": {"type": "string", "enum": ["exploration", "combat", "dialogue", "level_up", "map", "menu", "unknown"]},
                "visible_enemies": {"type": "array", "items": {"type": "string"}},
                "visible_party": {"type": "array", "items": {"type": "string"}},
                "visible_levels": {"type": "array", "items": {"type": "integer"}},
                "dialogue_or_warning": {"type": "string"},
                "evidence": {"type": "array", "items": {"type": "string"}},
            },
        },
        "candidates": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["checkpoint_id", "confidence", "reason"],
                "properties": {
                    "checkpoint_id": {"type": "string"},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    "reason": {"type": "string"},
                },
            },
        },
        "completion_candidates": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["step_id", "confidence", "reason"],
                "properties": {
                    "step_id": {"type": "string"},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    "reason": {"type": "string"},
                },
            },
        },
        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
    },
}


def _image_data_url(image_bytes: bytes, max_dimension: int) -> tuple[str, int, int]:
    image = Image.open(io.BytesIO(image_bytes))
    image.load()
    width, height = image.size
    if max(width, height) > max_dimension:
        image.thumbnail((max_dimension, max_dimension))
    if image.mode != "RGB":
        image = image.convert("RGB")
    output = io.BytesIO()
    image.save(output, format="JPEG", quality=84, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(output.getvalue()).decode("ascii"), width, height


def analyze_screenshot(
    image_bytes: bytes,
    content_type: str | None,
    context: str | None,
    settings: Settings,
    route: list[RouteCheckpoint],
    walkthrough: list[WalkthroughStep],
) -> VisionResult:
    if not settings.openrouter_api_key and not settings.openai_api_key:
        raise RuntimeError("OPENROUTER_API_KEY or OPENAI_API_KEY is not configured")
    data_url, width, height = _image_data_url(image_bytes, settings.max_image_dimension)
    candidates = [{"id": item.id, "name": item.name, "area": item.area, "enemies": item.enemies} for item in route]
    completion_steps = [
        {
            "id": item.id,
            "title": item.title,
            "kind": item.kind,
            "area": item.area,
            "completion_checks": item.completion_checks,
        }
        for item in walkthrough
    ]
    prompt = (
        "Analyze this Baldur's Gate 3 screenshot conservatively. Identify only visible evidence. "
        "Choose up to three current checkpoint candidates from the supplied checkpoint list. "
        "Add a completion candidate only when the frame directly shows a supplied completion check, "
        "such as an explicit quest/result notification, a named defeated enemy, or the reviewed resolved outcome. "
        "Location, absence of enemies, or merely being past an area is not completion evidence. "
        "Completion candidates are suggestions for player confirmation and never change progress themselves. "
        "If text or location is unclear, use unknown and low confidence. Context and checkpoint list:\n"
        + (context or "{}")
        + "\n"
        + json.dumps(candidates)
        + "\nWalkthrough steps and reviewed completion checks:\n"
        + json.dumps(completion_steps)
        + f"\nOriginal image size: {width}x{height}."
    )
    if settings.openrouter_api_key:
        response = httpx.post(
            OPENROUTER_URL,
            headers={
                "Authorization": f"Bearer {settings.openrouter_api_key}",
                "HTTP-Referer": "http://127.0.0.1:8787",
                "X-Title": "BG3 Honor Mode Assistant Visual Memory",
            },
            json={
                "model": settings.openrouter_model,
                "messages": [{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                }],
                "response_format": {
                    "type": "json_schema",
                    "json_schema": {"name": "bg3_screen_analysis", "strict": True, "schema": VISION_SCHEMA},
                },
                "temperature": 0.1,
                "max_tokens": 1000,
            },
            timeout=30,
        )
        response.raise_for_status()
        raw_content = response.json()["choices"][0]["message"]["content"]
        payload = json.loads(raw_content)
    else:
        response = OpenAI(api_key=settings.openai_api_key).responses.create(
            model=settings.openai_model,
            input=[{"role": "user", "content": [{"type": "input_text", "text": prompt}, {"type": "input_image", "image_url": data_url, "detail": "high"}]}],
            text={"format": {"type": "json_schema", "name": "bg3_screen_analysis", "strict": True, "schema": VISION_SCHEMA}},
        )
        payload = json.loads(response.output_text)
    detected = payload["detected"]
    return VisionResult(
        screen_summary=payload["screen_summary"],
        detected=ScreenDetected(**detected),
        candidates=[ScreenCandidate(**item) for item in payload["candidates"]],
        completion_candidates=[VisualCompletionCandidate(**item) for item in payload["completion_candidates"]],
        confidence=payload["confidence"],
    )
