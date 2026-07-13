# BG3 Honor Mode Assistant

A native macOS companion for safely navigating *Baldur's Gate 3* Honor Mode Act 1. A draggable Twilight Cleric pet sits above BG3, shows the next objective and danger, and opens a planner with route, fight preparation, party readiness, build ideas, map guidance, and contextual chat.

The planner uses native Liquid Glass on macOS 26 and a system material fallback on macOS 14–15, with a BG3-aligned translucent umber, bronze/gold frame, parchment hierarchy, and compact tooltip geometry. The collapsed pet defaults to middle-right between the minimap and hotbar; once moved, the player's chosen position persists across collapse, expansion, window changes, and relaunch. Its envelope adapts by tab: Current remains compact, while Party and Route receive only the additional height their content needs.

## What works

- Detects and launches BG3 through Steam app ID `1086940`.
- Loads all 19 reviewed Act 1 fight checkpoints from the guide.
- Uses the party's lowest level to choose a concrete activity: gain local exploration/dialogue XP, clear a safe mini encounter, or commit to the next core challenge. It finishes the current regional phase before entering the Underdark, Grymforge, or Crèche; the player can still override it.
- Persists the party-wide act, character levels/builds, checklist state, completed/skipped fights, and map calibration locally.
- Persists party names, class composition, prepared spells/capabilities, optional skip notes, muted checkpoints, and a pinned guide version per run.
- Warns when the lowest party member is below the guide minimum, preparation is unchecked, or prerequisites remain.
- Shows enemies, legendary actions, failure conditions, preparation, important notes, irreversible decisions, and completion criteria.
- Never completes a checkpoint from vision; the player must confirm, skip, or revisit it.
- Requires an explicit override before completing with unchecked conditions or crossing an irreversible checkpoint; skipped major objectives remain visible in the Act 2 gate.
- Samples the BG3 window about every two seconds and uses fast local OCR to detect the map.
- Registers Wilderness map artwork locally with ORB/RANSAC, then projects click-through markers through the recovered pan/zoom transform. Region bounds plus persisted calibration are the interior-map fallback.
- Keeps screenshots in memory. Only `DEBUG_CAPTURE=true` writes debug captures.
- Labels chat content as guide facts, assistant suggestions, or unknown information.
- Keeps the pet decision-first: next objective, minimum level, one run-ending risk, and Details/Ask/Done. Full tactics, completion checks, sources, and optional screen analysis stay collapsed until requested.
- Keeps the Twilight Cleric perfectly still at rest. Hovering the sprite plays its authored jump reaction and then uses all 16 v2 look directions to follow the pointer; leaving returns to the neutral frame without moving the overlay.
- Enforces one assistant instance per macOS user. Opening another copy—from the app bundle or an extracted ZIP—activates the existing assistant instead of creating a second pet or backend.

## Install a release build

Requirements: Apple-silicon Mac, macOS 14+, and BG3 via Steam.

1. Unzip `BG3-Honor-Mode-Assistant-<version>-macOS-arm64.zip`.
2. Move **BG3 Honor Mode Assistant.app** to Applications and open it.
3. Grant Screen Recording when prompted and relaunch. Capture verification starts automatically while BG3 is running; **Verify Capture Now** is an optional diagnostic.

The release app starts its embedded local backend automatically. It does not require Python, `uv`, Swift, the source checkout, or an API key. `OPENAI_API_KEY` is optional and only enables the explicit **Check screen** analysis.

## Source development

Requirements: macOS 14+, Swift 6, Python 3.11+, `uv`, and BG3 via Steam.

Start the development backend:

```sh
cd backend
cp ../.env.example .env
uv sync
uv run uvicorn app.main:app --host 127.0.0.1 --port 8787
```

`OPENAI_API_KEY` is optional for route, readiness, map, and deterministic chat.

Build and open the signed local app bundle:

```sh
cd mac
./scripts/build-app.sh
open -n "BG3 Honor Mode Assistant.app"
```

The build freezes and embeds the backend, copies the validated v2 pet from `~/.codex/pets/twilight-cleric/spritesheet.webp`, uses bundle ID `com.local.BG3HonorAssistant` by default, and signs with the first local Developer ID, Apple Development, or ad-hoc identity it can use.

For an unbundled source run:

```sh
cd mac
swift build
swift run BG3HonorAssistant
```

## Build a public release

Use a stable reverse-DNS bundle ID, a Developer ID Application certificate, and an `xcrun notarytool` keychain profile:

```sh
cd mac
BUNDLE_ID=com.yourcompany.BG3HonorAssistant \
NOTARY_PROFILE=bg3-honor-notary \
REQUIRE_RELEASE_SIGNING=1 \
./scripts/build-release.sh
```

The script verifies the signature, submits the ZIP for notarization, staples the app, rebuilds the final ZIP, runs Gatekeeper assessment, and prints its SHA-256. See [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) before distribution.

## Permissions and first run

Enable **BG3 Honor Mode Assistant** in System Settings → Privacy & Security → Screen Recording and relaunch the app. Start BG3 in windowed or borderless fullscreen; the app automatically verifies capture and starts the two-second local map detector. **Verify Capture Now** is available for troubleshooting but is not required to enable the loop.

Normal coaching and marker-queue alignment require only Screen Recording. The app does not synthesize input. An explicit Computer Use session may place the exported markers in BG3; that operator has separate macOS control authority and must be limited to the open map's custom-marker flow—never combat, movement, dialogue, inventory, or other gameplay input.

## User flow

1. Open the app and click **Launch BG3** if the game is not already running.
2. The small pet appears when BG3 is detected. It remains still until hovered; move across the sprite to wake it and change its gaze. Drag the surrounding tooltip background to reposition the overlay.
3. Read its next objective, minimum level, and single highest-risk mistake. Use **Done** to advance, **Details** for the fight card, or **Ask** for contextual chat. Screenshot checking is never required for progress. Right-click to snooze or mute checkpoint warnings.
4. In **Current**, scan **Do now**, **Don't die**, key Honor decisions, and **Prep**. Fight details, completion checks, sources, skip controls, and optional screen analysis are collapsed until requested. **Pin fight** returns to the combat card.
5. In **Route**, inspect or select any of the 19 checkpoints.
6. In **Party**, choose one act for the whole party, then configure one custom character plus three story companions. Set everyone to one level or adjust each member and choose a reviewed build. Each card shows only what to take/do at the current level plus the selected act's recommended equipment, acquisition location, and Act 1 map action—never a next-level teaser. Assigning a build assumes its reviewed setup; class/capability deviations stay under **Advanced**. The control window's **Party Loadout** button opens this view directly.
7. In **Chat**, ask what is next, which dialogue choice to make, how to avoid dying, or whether the party is ready. **Check screen** is optional evidence and never changes progress.
8. In the localhost map, choose **Export BG3 markers**. The queue is derived from the selected act, lowest party level, assigned builds, completed fights, and equipped gear. Opening the preview temporarily sends those exact labels to the in-game click-through overlay and can also download the versioned JSON manifest.
9. Open the BG3 map. The local matcher aligns the active queue as the map pans or zooms. A Computer Use session can then create only those named custom markers. After screenshot verification, click **Placed in BG3**; the fingerprint is persisted, repeat exports show `Already placed`, and the temporary overlay clears.
10. The Act 2 gate remains visible throughout the planner. Resolve displayed pending or skipped major/irreversible objectives before advancing.

## Local Act 1 browser map

The backend serves a fast companion map at [http://127.0.0.1:8787/map](http://127.0.0.1:8787/map). It uses MapGenie's Wilderness raster tiles with attribution and overlays guide fights plus Act 1 build equipment. Party gear actions open the selected build or exact item at the character's current level. Acts 2–3 already use the same gear schema, but their map actions remain disabled until those maps are reviewed. The app does not copy or impersonate the MapGenie website; **Open MapGenie Wilderness** links to the original service.

The map supports region, level, build, type, completion, label, and search filters. Its **Party** tab preserves all four character names, individual levels, and selected builds from the native companion and shows only each character's current-level action. **Equipment** is a separate, act-scoped tab grouped by party member; assignments persist independently per character and every item can be opened on the map. Exact and area-level pins are visually distinguished so coarse item sources do not claim false precision. Marker export is phase-aware: it includes safe unresolved fights in the current route region and unequipped equipment for the selected builds. Fight levels remain guide facts; equipment labels use the selected party level and are identified as assistant suggestions.

## Verification

```sh
cd backend && uv run pytest -q
cd ../mac
swiftc BG3Assistant/BG3Models.swift BG3Assistant/BG3Detector.swift BG3Assistant/MapOpenDetector.swift BG3Assistant/RunStore.swift BG3Assistant/OverlayMetrics.swift BG3Assistant/PetAnimationModel.swift ModelTests/main.swift -o /tmp/bg3-model-tests
/tmp/bg3-model-tests
swift build
./scripts/build-app.sh
./scripts/build-release.sh
```

See [`COMPLETION_AUDIT.md`](COMPLETION_AUDIT.md) for requirement-by-requirement evidence and the remaining packaged map-overlay check.

## Data and grounding

- `data/act1_fights.json`: source fight facts and world coordinates.
- `data/act1_route.json`: reviewed order, prerequisites, danger, failure conditions, and gates.
- `data/build_overview.tsv`, `build_levels.tsv`, `build_gear.tsv`: reviewed build and equipment data. Build entries are presented as ideas unless their level plan has been reviewed.
- Active run: `~/Library/Application Support/BG3HonorAssistant/run.json`; per-run snapshots: `~/Library/Application Support/BG3HonorAssistant/runs/<run-id>.json`.
- Embedded-backend state and logs: `~/Library/Application Support/BG3HonorAssistant/backend` and `~/Library/Application Support/BG3HonorAssistant/debug`.
- The run's guide version is pinned. A newer backend guide is reported but does not silently rewrite an active run.

Primary fight source: [BG3 Honor Mode guide](https://docs.google.com/spreadsheets/d/1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0). Map reference: [MapGenie Wilderness](https://mapgenie.io/baldurs-gate-3/maps/wilderness).

## Limitations

- Wilderness alignment is automatic because the in-game map and reference mosaic share artwork; synthetic tests cover 0.55×–3.5× zoom. Interior regions use coordinate bounds and may need manual calibration because they are not on the Wilderness mosaic.
- Live BG3 process detection, real-window capture, live non-map rejection, and positive registration of a real 2560×1440 Wilderness map are verified. The fixed packaged marker panel still needs one visible pan/zoom alignment observation in the game.
- Map registration requires the local MapGenie tile cache to be available. OCR plus saved region calibration is the offline fallback.
- Fast OCR depends on recognizable English map labels. The overlay hides when the detector is not confident.
- True exclusive fullscreen can place macOS panels behind the game; use windowed or borderless fullscreen.
- BG3 may be discovered across macOS Spaces, but a fully minimized or unavailable Metal window cannot be captured until it is restored.
- No game-memory reading, mods, save editing, combat automation, general gameplay input control, or continuous cloud vision. The native app never synthesizes input; an external, explicit Computer Use session may operate only the open BG3 custom-marker flow from the exported manifest.
- The current local `0.1.0` artifact is Apple Development-signed and therefore not a public Gatekeeper-ready download. Public distribution is blocked only on the publisher's Developer ID certificate, final bundle ID, and notarization profile; the release script enforces those when `REQUIRE_RELEASE_SIGNING=1`.
