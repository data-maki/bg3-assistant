---
name: verify
description: How to build, launch, and observe the BG3 overlay mac app for verification on this machine.
---

# Verifying the mac overlay app

## Build

```bash
cd mac && swift build            # debug
swift build -c release --scratch-path .build
```

No Xcode on this machine (CLT only): `swift test` fails with "no such
module 'XCTest'". The test target in Package.swift is for CI/Xcode
machines. Verify pure logic with a standalone runner instead:
compile `BG3Models.swift AbilityProgression.swift <logic>.swift main.swift`
with `swiftc` (BG3Models only imports Foundation) and run assertions.

## Launch without disturbing the user's instance

- A `SingleInstanceGuard` locks `~/Library/Application Support/
  BG3HonorAssistant/instance.lock` and **force-terminates any other
  BG3HonorAssistant process**. Never launch a second instance while the
  packaged app runs — quit it first (`osascript -e 'quit app "BG3 Honor
  Mode Assistant"'`), verify, then `open "mac/BG3 Honor Mode
  Assistant.app"` to restore. State is SQLite-persisted on every
  mutation, so quit/relaunch is safe by design.
- Isolate state with `BG3_ASSISTANT_STATE_DIR=<tmpdir>`. Seed a run by
  writing `run.json` into that dir (RunStore migrates it into SQLite on
  first load) — party members, `buildId`s (e.g. `SB-1011`, `CL-102`),
  and `gearTarget` all round-trip.
- The debug binary self-manages the backend: it spawns
  `backend/.venv/bin/uvicorn` on 8787 and retires unowned packaged
  backends. Get build/gear data from `GET /api/act1/route` (there is no
  `/builds` endpoint; see `/openapi.json`).

## Drive

The agent shell has **no Screen Recording and no assistive-access TCC**:
`screencapture` and System Events clicks/AX reads fail. Use the dev
hook instead:

```bash
BG3_ASSISTANT_STATE_DIR=<tmpdir> BG3_ASSISTANT_DEBUG_TAB=route \
  mac/.build/arm64-apple-macosx/debug/BG3HonorAssistant
```

`BG3_ASSISTANT_DEBUG_TAB` (now|route|party|loadout|act|chat|settings)
launches with the planner expanded on that tab, so each tab renders at
startup with real backend data. Evidence = process stays alive ~10s +
app log free of SwiftUI warnings/crashes + post-run SQLite state.
Launch once per tab; probe bad state by seeding a corrupt `run.json`.

`mac/DebugCapture` only screenshots the **game** window (com.larian.bg3),
not the overlay — useless unless BG3 is running.
