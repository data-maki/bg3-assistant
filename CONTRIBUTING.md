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

## Verification

Run `swift build` from `mac/` and exercise the changed player flow locally. Keep test sources, screenshots, workbooks, and reports in ignored internal folders.

For packaging and signing, see [`docs/developers/RELEASE.md`](docs/developers/RELEASE.md).

## Pull requests

Explain the player problem, the smallest behavior change, and how it was verified. UI changes should include a local screenshot in the pull request description, not as a committed repository artifact.
