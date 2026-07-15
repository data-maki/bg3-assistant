# Chat: history-aware grounding, Exa web search with citations, markdown answers

**Date:** 2026-07-14
**Status:** Implemented in the same session (autonomous run; user spec was explicit).

## Problem

The in-game chat (`backend/app/guide_chat.py` + `backend/app/llm_chat.py`) answers each
question in isolation and verbosely:

- No conversation history is sent, so follow-ups ("what about the second option?") lose context.
- Run-state grounding is stuffed into the user message, not the system prompt.
- The LLM's prose is appended *after* the full deterministic blob, so answers are long and
  the main point is buried — bad for a small overlay window used mid-game.
- No web search: anything outside the reviewed Act-1 guide is a dead end, forcing players
  to alt-tab to wikis.
- The Mac overlay renders plain text — no markdown, no clickable links, no images.

## Design

### Backend

1. **Models** (`models.py`)
   - `ChatTurn { role: "user"|"assistant", content }`; `ChatRequest.history: list[ChatTurn]`.
   - `ChatSource { title, url, snippet }`; `ChatResponse.sources: list[ChatSource]`.
2. **Config** (`config.py`): `EXA_API_KEY` setting; key added to `backend/.env` and
   `.env.example`.
3. **Web search** (`web_search.py`, new): thin Exa `/search` client (httpx, `x-api-key`),
   `type: auto`, ~4 results with short text snippets, returns `list[ChatSource]`.
4. **LLM chat** (`llm_chat.py` rewrite, same public `answer()` signature):
   - System prompt now carries the style contract (main point first, ≤ ~60 words, markdown,
     bold the key action) **plus** the guide facts and authority-labelled run state.
   - Messages: system → last 8 history turns (clipped) → current question (+ optional image).
   - `search_web` tool offered when the Exa key is set; up to 2 tool rounds, then a forced
     final answer. Model is told to search only when the guide facts don't cover the question
     and to cite results as inline markdown links, never inventing URLs.
   - **Search nudge** (found in live testing): Gemini flash weighs user-turn tool guidance
     far more than the system prompt — gemini-2.5-flash never volunteered a search (it cited
     URLs from memory or refused), while gemini-3-flash-preview over-searched guide-covered
     questions. A one-line user-turn suffix phrased as a two-way gate ("answer from the
     guide facts when they cover this; call search_web only when they do not") routes both
     directions correctly on gemini-3-flash-preview, the default model.
   - **Citation gate** (deterministic): every markdown URL in the final answer must match a
     URL an executed search returned (compared per page, fragment ignored). If the model
     cited from memory, one best-effort Exa search on the player's question runs; links that
     still can't be verified collapse to their label and unverified images are dropped. No
     fake references can reach the player.
   - LLM markdown becomes the **primary** `answer`; deterministic facts stay in
     `guide_facts` / `assistant_suggestions` / `unknowns`. Any failure → deterministic
     fallback unchanged (existing safety property preserved: route truth stays reviewed,
     the model cannot mark progress).
5. **Deterministic chat** (`guide_chat.py`): unchanged — it is the offline fallback and its
   format is asserted by existing tests.

### Mac overlay

- `BG3Models.swift`: `ChatTurn`, `ChatSource`, `ChatRequest.history`,
  `ChatResponse.sources` (optional for backward compat).
- `AppState.swift`: `ChatLine` carries `sources`; `sendChat` sends the last 8 chat lines as
  history and stores response sources on the assistant line.
- `ChatTabView.swift`: assistant bubbles render markdown via
  `AttributedString(markdown:)` (inline syntax, whitespace preserved — links are clickable),
  `![alt](url)` images are extracted and shown with `AsyncImage`, and sources render as a
  tappable link-chip row under the bubble.

## Alternatives considered

- **Always-on Exa search per question** — rejected: adds latency to every in-game answer;
  most questions are covered by the reviewed guide.
- **Keyword heuristic to trigger search** — rejected: brittle; the model with a tool call
  decides better and only pays the cost when needed.
- **Replacing the deterministic path with the LLM entirely** — rejected: the deterministic
  path is the always-available fallback and the safety anchor for route facts.

## Testing

- `test_llm_chat.py`: grounding moved to system prompt, history included in messages,
  tool-call round executes Exa and returns cited sources, fallback behaviour unchanged.
- `test_web_search.py` (new): hermetic Exa client tests (monkeypatched httpx).
- Existing deterministic tests untouched and still green.
- **Key hygiene**: `.env` files are gitignored and never contain tests' keys; an autouse
  conftest fixture deletes `*_API_KEY` env vars (loaded into the process by
  `app.config`'s `load_dotenv`) and clears the `get_settings` cache before every test, so
  no test can silently use the developer's real keys. A canary test
  (`test_settings_in_tests_never_see_real_keys`) fails if that guarantee is removed.

## Shipping note

The Mac app runs a **frozen** PyInstaller backend; backend + Swift changes require
rebuilding the bundle before they show up in the installed app (see RELEASE_CHECKLIST.md).
For the frozen app, `EXA_API_KEY` must also be present in the per-user state root `.env`.
