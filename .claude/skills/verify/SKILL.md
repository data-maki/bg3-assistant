---
name: verify
description: How to build, launch, and observe the BG3 overlay mac app for verification on this machine.
---

# Verifying the mac overlay app

## Build

```bash
./scripts/macos/validate.sh
```

This runs the Swift build and tests plus the explicit Xcode project build. The
Xcode build matters because the project has a manually maintained
source/resource list. All output stays under `artifacts/macos/build/`.

For an isolated manual Xcode build:

```bash
xcodebuild -project mac/BG3HonorAssistant.xcodeproj \
  -scheme BG3HonorAssistant -configuration Debug \
  -derivedDataPath artifacts/macos/build/manual-xcode \
  CODE_SIGNING_ALLOWED=NO build
```

## Launch without disturbing the user's instance

- A `SingleInstanceGuard` locks `~/Library/Application Support/
  BG3HonorAssistant/instance.lock` and **force-terminates any other
  BG3HonorAssistant process**. Never launch a second instance while the
  packaged app runs — quit it first (`osascript -e 'quit app "BG3 Honor
  Mode Assistant"'`), verify, then
  `open "artifacts/macos/app/BG3 Honor Mode Assistant.app"` to restore.
  State is SQLite-persisted on every
  mutation, so quit/relaunch is safe by design.
- Isolate state with `BG3_ASSISTANT_STATE_DIR=<tmpdir>`. A fresh dir
  seeds a default run (SQLite only — the old `run.json` migration was
  removed). To seed custom state, launch once, then rewrite
  `snapshot_json` in the `runs` table of `state.sqlite3` — party
  members, `buildId`s (e.g. `SB-1011`, `CL-102`), and `gearTarget`
  all round-trip.
- The app loads guide/build/item data from bundled `guide-bundle.json`.
  It must not launch Python or connect to localhost port 8787.
- Local AI uses bundled Ollama on `127.0.0.1:11435`; it starts only when
  Local Qwen is selected. A first launch with no provider must not start it.
- OpenRouter credentials are in Keychain and must never appear in app
  resources, logs, command arguments, or the Ollama child environment.

## Drive

The agent shell has **no Screen Recording and no assistive-access TCC**:
`screencapture` and System Events clicks/AX reads fail. Use the dev
hook instead:

```bash
BG3_ASSISTANT_STATE_DIR=<tmpdir> BG3_ASSISTANT_DEBUG_TAB=route \
  artifacts/macos/build/validation/arm64-apple-macosx/debug/BG3HonorAssistant
```

`BG3_ASSISTANT_DEBUG_TAB` (now|route|party|loadout|act|chat|settings)
launches with the planner expanded on that tab, so each tab renders at
startup with bundled guide data. Evidence = process stays alive ~10s +
app log free of SwiftUI warnings/crashes + post-run SQLite state.
Launch once per tab; probe bad state by corrupting `snapshot_json` in
the seeded `state.sqlite3`.

For a release bundle, verify `Contents/Resources/Data/guide-bundle.json`,
`Contents/Resources/ItemIcons/safeguard-shield.webp`, and
`Contents/Resources/ollama/ollama` exist, `Contents/Resources/backend` does
not exist, `codesign --verify --deep --strict` passes, and the bundled Ollama
reports the pinned version under a clean environment.

`tools/debug-capture` only screenshots the **game** window (com.larian.bg3),
not the overlay — useless unless BG3 is running.
