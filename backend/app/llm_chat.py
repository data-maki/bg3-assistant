"""Guide-grounded LLM chat via OpenRouter.

The reviewed guide stays the source of truth: the model is handed the current
checkpoint/step facts as grounding and told to answer from them, flag anything
it is unsure of, and never invent route facts or mark progress. It can also see
an attached BG3 screenshot (cheap vision model) to answer "what am I looking
at" questions. Any failure falls back to the deterministic keyword chat so the
overlay always answers.
"""

from __future__ import annotations

import logging

import httpx

from . import guide_chat
from .config import Settings
from .models import ChatRequest, ChatResponse, RouteCheckpoint, WalkthroughStep

logger = logging.getLogger("bg3.llm_chat")

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

SYSTEM_PROMPT = (
    "You are a Baldur's Gate 3 Honor Mode assistant embedded in an overlay. "
    "Answer the player's question about their current objective using the GUIDE FACTS "
    "provided below as the source of truth. Be concise and specific — two or three short "
    "sentences, plain language, lead with the action to take. "
    "If a screenshot is attached, use it to ground your answer to what is on screen. "
    "Never invent level requirements, quest steps, or item locations that are not in the "
    "guide facts; if the guide does not cover it, say so briefly. Never tell the player an "
    "objective is complete — that is their call."
)


def _user_content(request: ChatRequest, grounding: str) -> list | str:
    text = f"GUIDE FACTS:\n{grounding}\n\nPLAYER QUESTION: {request.message}"
    if request.screenshot_context:
        timestamp = f" at unix {request.screenshot_timestamp:.0f}" if request.screenshot_timestamp else ""
        text += f"\n\n(Player's latest screen note{timestamp}; local evidence only: {request.screenshot_context[:400]})"
    if not request.image_base64:
        return text
    return [
        {"type": "text", "text": text},
        {
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{request.image_base64}"},
        },
    ]


def answer(
    checkpoint: RouteCheckpoint,
    request: ChatRequest,
    step: WalkthroughStep | None,
    settings: Settings,
) -> ChatResponse:
    """LLM answer grounded in the guide; deterministic fallback on any failure."""
    deterministic = guide_chat.answer(checkpoint, request, step)
    if not settings.openrouter_api_key:
        return deterministic

    payload = {
        "model": settings.openrouter_model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _user_content(request, "\n".join(guide_chat.grounding_facts(checkpoint, request, step)))},
        ],
        "max_tokens": 400,
        "temperature": 0.3,
    }
    try:
        response = httpx.post(
            OPENROUTER_URL,
            headers={
                "Authorization": f"Bearer {settings.openrouter_api_key}",
                "HTTP-Referer": "http://127.0.0.1:8787",
                "X-Title": "BG3 Honor Mode Assistant",
            },
            json=payload,
            timeout=30,
        )
        response.raise_for_status()
        text = response.json()["choices"][0]["message"]["content"].strip()
        if not text:
            raise ValueError("empty completion")
    except Exception:
        logger.warning("OpenRouter chat failed; using deterministic fallback", exc_info=True)
        return deterministic

    # Route truth and the primary risk remain deterministic. Model prose is a
    # labelled secondary explanation, never a replacement for fact authority.
    return deterministic.model_copy(update={
        "answer": deterministic.answer + "\n\nAssistant explanation: " + text,
        "assistant_suggestions": [*deterministic.assistant_suggestions, text],
    })
