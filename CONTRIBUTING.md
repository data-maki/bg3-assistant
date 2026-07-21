# Contributing

BG3 Honor Mode Assistant is a focused in-game companion. Contributions should make the next player decision clearer without turning the overlay into a dashboard.

## Before opening a change

- Search existing issues and keep each pull request focused on one problem.
- Keep route facts sourced. Suggestions must remain visibly separate from guide facts and player-confirmed state.
- Do not add mods, game-memory access, save editing, automated input, periodic screen capture, or background recording. One-shot chat attachments are the intentional capture boundary.
- Keep the main player flow inside the native overlay. Public map handoff is the intentional exception.
- Describe how you verified behavior changes. Internal tests and generated QA evidence are intentionally kept outside the public repository.

## Development setup

App requirements: macOS 14+ and Swift 6. Python 3.11+ and [`uv`](https://docs.astral.sh/uv/) are needed only for backend data tooling, evaluations, and backend tests.

The editable app source is `mac/BG3Assistant/`. Build scripts are in `scripts/macos/`, and all generated output is isolated under the gitignored `artifacts/macos/` directory.

```sh
./scripts/macos/validate.sh
./scripts/macos/build-app.sh
open "artifacts/macos/app/BG3 Honor Mode Assistant.app"
```

The app loads its generated guide bundle directly. Configure Local Qwen or an OpenRouter key in onboarding or Settings; OpenRouter credentials are stored in macOS Keychain.

For backend data tooling and evaluations:

```sh
cd backend
uv sync --extra dev
uv run pytest -q
```

`backend/.env` may contain provider settings for backend-only evaluations. The macOS app does not read that file and no credential may be copied into a release bundle.

## Verification

Run `./scripts/macos/validate.sh` from the repository root and `uv run --extra dev pytest` from `backend/`, then exercise the changed player flow locally. Keep screenshots, workbooks, and reports in ignored internal folders.

For packaging and signing, see [`docs/developers/RELEASE.md`](docs/developers/RELEASE.md).

## Pull requests

Explain the player problem, the smallest behavior change, and how it was verified. UI changes should include a local screenshot in the pull request description, not as a committed repository artifact.
