"""Guide-grounded LLM chat via OpenRouter.

The reviewed guide stays the source of truth: guide facts and the
authority-labelled run snapshot are injected into the system prompt, prior
turns ride along as conversation history, and the model may call an Exa web
search tool for questions the guide does not cover — citing results as inline
markdown links the overlay renders clickable. Answers are short markdown with
the main point first, sized for the in-game chat window. Any failure falls
back to the deterministic keyword chat so the overlay always answers.
"""

from __future__ import annotations

import json
import logging
import re

import httpx

from . import guide_chat, web_search
from .config import Settings
from .models import ChatRequest, ChatResponse, ChatSource, RouteCheckpoint, WalkthroughStep

logger = logging.getLogger("bg3.llm_chat")

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

HISTORY_TURNS = 8
HISTORY_TURN_CHARACTERS = 600
MAX_SEARCH_ROUNDS = 2
MAX_SOURCES = 5

SYSTEM_PROMPT = """\
You are a Baldur's Gate 3 Honor Mode assistant inside a small in-game overlay chat. \
The player is mid-game and reads answers in a narrow window, so:
- Lead with the answer. First line = the action to take or the fact asked for; put the key action in **bold**.
- Stay under ~60 words unless the player explicitly asks for detail. No preamble, no restating the question.
- Use GitHub-flavored markdown: **bold**, short bullet lists (3 items max), inline links.
- You may embed at most one image with ![alt](url), and only a URL taken from web search results.

Grounding rules:
- The GUIDE FACTS below are the reviewed route source of truth. Lines are authority-labelled; \
treat [Guide fact] as certain, [Player state]/[Player-confirmed ...] as the player's actual run, \
and [Assistant suggestion] as an unverified hint.
- Never invent level requirements, quest steps, or item locations that are not in the guide facts or search results.
- Never tell the player an objective is complete — that is their call.

Web search (when the search_web tool is available):
- Answer from the guide facts when they cover the question; call search_web only when they do not.
- Cite every claim taken from a search result as an inline markdown link, e.g. ([bg3.wiki](https://bg3.wiki/...)).
- Never write a URL that was not returned by search_web in this conversation — not even one you know from memory. \
No search performed = no links in the answer.

GUIDE FACTS AND CURRENT RUN STATE:
{grounding}"""

SEARCH_TOOL = {
    "type": "function",
    "function": {
        "name": "search_web",
        "description": (
            "Search the web for Baldur's Gate 3 information the guide facts do not cover "
            "(other acts, mechanics, items, patch behaviour). Returns titled results with "
            "URLs and snippets; cite them as inline markdown links."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Web search query, e.g. 'bg3 honour mode Grym fight strategy'."},
            },
            "required": ["query"],
        },
    },
}


def _history_messages(request: ChatRequest) -> list[dict]:
    return [
        {"role": turn.role, "content": turn.content[:HISTORY_TURN_CHARACTERS]}
        for turn in request.history[-HISTORY_TURNS:]
        if turn.content.strip()
    ]


# Gemini flash weighs user-turn tool guidance far more than the system prompt.
# Phrased as a two-way gate: guide-covered questions answer directly (no
# search latency), out-of-guide questions search instead of declining or
# citing from memory. Verified against gemini-3-flash-preview.
SEARCH_NUDGE = (
    "\n\n(Answer from the guide facts when they cover this; call search_web only when they do not — "
    "never decline, and never cite links from memory.)"
)


def _user_content(request: ChatRequest, allow_search: bool) -> list | str:
    text = request.message
    if allow_search:
        text += SEARCH_NUDGE
    if not request.image_base64:
        return text
    text += "\n\nThe player attached their current BG3 window. Use visible details as context, not as confirmed run state."
    return [
        {"type": "text", "text": text},
        {
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{request.image_base64}"},
        },
    ]


def _run_search_calls(tool_calls: list[dict], settings: Settings) -> tuple[list[dict], list[ChatSource]]:
    """Execute the model's search_web calls; tool messages plus collected sources."""
    messages: list[dict] = []
    sources: list[ChatSource] = []
    for call in tool_calls:
        try:
            arguments = json.loads(call["function"].get("arguments") or "{}")
        except (ValueError, TypeError):
            arguments = {}
        results = web_search.search(str(arguments.get("query", "")), settings.exa_api_key)
        sources.extend(results)
        messages.append(
            {
                "role": "tool",
                "tool_call_id": call.get("id", ""),
                "content": json.dumps([source.model_dump() for source in results]) if results else "No results.",
            }
        )
    return messages, sources


_MARKDOWN_IMAGE = re.compile(r"!\[[^\]]*\]\((https?://[^)\s]+)\)")
_MARKDOWN_LINK = re.compile(r"\[([^\]]*)\]\((https?://[^)\s]+)\)")


def _page_key(url: str) -> str:
    return url.split("#", 1)[0].rstrip("/")


def _reconcile_citations(text: str, sources: list[ChatSource], request: ChatRequest, settings: Settings) -> tuple[str, list[ChatSource]]:
    """Keep only links a real search returned; models cite from memory otherwise.

    Any markdown URL that no executed search produced gets one best-effort Exa
    check on the player's question; still-unverified links collapse to their
    label (images are dropped) so every clickable reference is real. URLs are
    compared per page (fragment ignored). Returns the cleaned text plus the
    deduped sources, cited ones first, capped at MAX_SOURCES.
    """

    def verified_keys(items: list[ChatSource]) -> set[str]:
        return {_page_key(source.url) for source in items} | {_page_key(source.image) for source in items if source.image}

    cited = {_page_key(match.group(1)) for match in _MARKDOWN_IMAGE.finditer(text)}
    cited.update(_page_key(match.group(2)) for match in _MARKDOWN_LINK.finditer(text))
    verified = verified_keys(sources)
    if cited - verified and settings.exa_api_key:
        query = request.message if "baldur" in request.message.lower() else f"Baldur's Gate 3 {request.message}"
        sources = [*sources, *web_search.search(query, settings.exa_api_key)]
        verified = verified_keys(sources)
    text = _MARKDOWN_IMAGE.sub(lambda m: m.group(0) if _page_key(m.group(1)) in verified else "", text)
    text = _MARKDOWN_LINK.sub(lambda m: m.group(0) if _page_key(m.group(2)) in verified else m.group(1), text)

    unique: dict[str, ChatSource] = {}
    for source in sources:
        unique.setdefault(source.url, source)
    ranked = sorted(unique.values(), key=lambda source: _page_key(source.url) not in cited)
    return text.strip(), ranked[:MAX_SOURCES]


def _completion(messages: list[dict], settings: Settings, allow_tools: bool) -> dict:
    payload = {
        "model": settings.openrouter_model,
        "messages": messages,
        "max_tokens": 400,
        "temperature": 0.3,
    }
    if allow_tools:
        payload["tools"] = [SEARCH_TOOL]
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
    return response.json()["choices"][0]["message"]


def answer(
    checkpoint: RouteCheckpoint | None,
    request: ChatRequest,
    step: WalkthroughStep | None,
    settings: Settings,
) -> ChatResponse:
    """LLM answer grounded in the guide; deterministic fallback on any failure."""
    if not settings.openrouter_api_key:
        return guide_chat.answer(checkpoint, request, step)

    sources: list[ChatSource] = []
    try:
        grounding = "\n".join(guide_chat.grounding_facts(checkpoint, request, step))
        messages: list[dict] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(grounding=grounding)},
            *_history_messages(request),
            {"role": "user", "content": _user_content(request, allow_search=bool(settings.exa_api_key))},
        ]
        text = ""
        for search_round in range(MAX_SEARCH_ROUNDS + 1):
            allow_tools = bool(settings.exa_api_key) and search_round < MAX_SEARCH_ROUNDS
            message = _completion(messages, settings, allow_tools)
            tool_calls = message.get("tool_calls") or []
            if not tool_calls:
                text = (message.get("content") or "").strip()
                break
            messages.append({"role": "assistant", **message})
            tool_messages, round_sources = _run_search_calls(tool_calls, settings)
            messages.extend(tool_messages)
            sources.extend(round_sources)
        if not text:
            raise ValueError("empty completion")
    except Exception:
        logger.warning("OpenRouter chat failed; using deterministic fallback", exc_info=True)
        return guide_chat.answer(checkpoint, request, step)

    text, sources = _reconcile_citations(text, sources, request, settings)
    return ChatResponse(answer=text, sources=sources)
