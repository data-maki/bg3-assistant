"""Exa web search for chat questions the reviewed guide does not cover.

Results are returned as ChatSource entries (title, url, snippet) so the model
can cite them inline and the overlay can render clickable references. Failures
return an empty list: web search is best-effort flavour, never a hard
dependency of the chat.
"""

from __future__ import annotations

import logging

import httpx

from .models import ChatSource

logger = logging.getLogger("bg3.web_search")

EXA_SEARCH_URL = "https://api.exa.ai/search"
SNIPPET_CHARACTERS = 500


def search(query: str, api_key: str, num_results: int = 4) -> list[ChatSource]:
    """Top web results for a query, each with a short text snippet."""
    if not api_key or not query.strip():
        return []
    payload = {
        "query": query,
        "type": "auto",
        "numResults": num_results,
        "contents": {"text": {"maxCharacters": SNIPPET_CHARACTERS}},
    }
    try:
        response = httpx.post(
            EXA_SEARCH_URL,
            headers={"x-api-key": api_key},
            json=payload,
            timeout=15,
        )
        response.raise_for_status()
        results = response.json().get("results", [])
    except Exception:
        logger.warning("Exa search failed; answering without web results", exc_info=True)
        return []
    return [
        ChatSource(
            title=(item.get("title") or item.get("url", "")).strip(),
            url=item["url"],
            snippet=(item.get("text") or "").strip(),
            image=item.get("image") or "",
        )
        for item in results
        if item.get("url")
    ]
