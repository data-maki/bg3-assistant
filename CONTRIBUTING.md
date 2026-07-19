# Contributing

BG3 Honor Mode Assistant is a focused in-game companion. Contributions should make the next player decision clearer without turning the overlay into a dashboard.

## Before opening a change

- Search existing issues and keep each pull request focused on one problem.
- Keep route facts sourced. Suggestions must remain visibly separate from guide facts and player-confirmed state.
- Do not add mods, game-memory access, save editing, automated input, periodic screen capture, or background recording. One-shot chat attachments are the intentional capture boundary.
- Keep the main player flow inside the native overlay. The local browser map is the intentional exception.
- Describe how you verified behavior changes. Internal tests and generated QA evidence are intentionally kept outside the public repository.

## Development setup

Requirements: macOS 14+, Swift 6, Python 3.11+, and [`uv`](https://docs.astral.sh/uv/).

```sh
cd backend
cp ../.env.example .env
uv sync
uv run uvicorn app.main:app --host 127.0.0.1 --port 8787
```

In another terminal:

```sh
cd mac
swift run BG3HonorAssistant
```

`BG3_BACKEND_URL` defaults to `http://127.0.0.1:8787`, so local development uses the provider settings in `backend/.env`. To exercise the keyless proxy path, set it to an HTTPS hosted backend before launching the app:

```sh
BG3_BACKEND_URL=https://assistant.example.com swift run BG3HonorAssistant
```

Hosted mode requires an Apple-signed AppTransaction and the server variables documented in `docs/developers/RELEASE.md`. Direct `swift run` builds may not have an App Store transaction, so guide-only behavior is the expected fallback unless StoreKit sandbox is configured.

## Verification

Run `swift build` from `mac/` and `uv run --extra dev pytest` from `backend/`, then exercise the changed player flow locally. Keep screenshots, workbooks, and reports in ignored internal folders.

For packaging and signing, see [`docs/developers/RELEASE.md`](docs/developers/RELEASE.md).

## Pull requests

Explain the player problem, the smallest behavior change, and how it was verified. UI changes should include a local screenshot in the pull request description, not as a committed repository artifact.
