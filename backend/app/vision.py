import base64
import io
import json

from openai import OpenAI
from PIL import Image

from .config import Settings
from .models import RouteCheckpoint, ScreenCandidate, ScreenDetected, VisionResult


VISION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["screen_summary", "detected", "candidates", "confidence"],
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
) -> VisionResult:
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")
    data_url, width, height = _image_data_url(image_bytes, settings.max_image_dimension)
    candidates = [{"id": item.id, "name": item.name, "area": item.area, "enemies": item.enemies} for item in route]
    prompt = (
        "Analyze this Baldur's Gate 3 screenshot conservatively. Identify only visible evidence. "
        "Choose up to three checkpoint candidates from the supplied list; never claim progress is complete. "
        "If text or location is unclear, use unknown and low confidence. Context and checkpoint list:\n"
        + (context or "{}")
        + "\n"
        + json.dumps(candidates)
        + f"\nOriginal image size: {width}x{height}."
    )
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
        confidence=payload["confidence"],
    )
