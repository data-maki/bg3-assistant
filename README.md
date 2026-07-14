# BG3 Honor Mode Assistant

A native macOS companion for safely navigating *Baldur's Gate 3* Honor Mode Act 1. A draggable Twilight Cleric pet sits above BG3, shows the next objective and danger, and opens a planner with route, fight preparation, party readiness, build ideas, map guidance, and contextual chat.

The planner uses native Liquid Glass on macOS 26 and a system material fallback on macOS 14–15, with a BG3-aligned translucent umber, bronze/gold frame, parchment hierarchy, and compact tooltip geometry. The collapsed pet defaults to middle-right between the minimap and hotbar; once moved, the player's chosen position persists across collapse, expansion, window changes, and relaunch. Its envelope adapts by tab: Current remains compact, while Party and Route receive only the additional height their content needs.

## What works

- Detects and launches BG3 through Steam app ID `1086940`.
- Verifies ownership of its packaged localhost backend at startup, replacing an orphaned previous-release process before loading guide data.
- Loads all 19 reviewed Act 1 fight checkpoints from the guide.
- Adds a 59-step, 11-phase Act 1 walkthrough around those fights: exploration XP, mini encounters, pickups, 15 dialogue/decision challenges, and progression gates. Shovel, the Necromancy of Thay, Mourning Frost, a Sussur weapon, and the Blood of Lathander are separate confirmable power steps. The player explicitly marks each step Done, Skipped, or Revisit; vision never changes walkthrough progress.
- Treats consequential dialogue as route state. The pet's **Dialogue** action opens the current or upcoming conversation with its safe intent, no-go choice, tradeoffs, and irreversible outcome before the next fight.
- Adds run-ending incident protocols with `TRIGGER`, `DO`, `NEVER`, `IF IT GOES WRONG`, and the Honor-only delta. Only encounter-specific, non-obvious aftermath is retained behind detail disclosure. Optional bosses explain reward, risk, skip cost, and the last safe return point.
- Keeps recommendations advisory: **Focus this** pins any unresolved fight, dialogue, pickup, or exploration step without rewriting the reviewed route. The current card clearly distinguishes `YOUR FOCUS` from the assistant's recommendation and offers a local lower-risk alternative when one exists.
- Removes resolved work from active surfaces. Done and Skipped activities move immediately into a collapsed **Archive**, retain their outcome, and return to active guidance through **Revisit**.
- Uses explicit `EXPLORE`, `PREFLIGHT`, `DIALOGUE`, `COMBAT`, and `LEVEL UP` presentation. Player-confirmed fight completion archives the encounter and advances immediately.
- Offers Minimal, Focus, and Reference collapsed densities. Minimal is pet-only; holding **Option-Space** temporarily reveals the Focus card without requiring Input Monitoring.
- Shows the safest incomplete step for the party's lowest level without bouncing between regions. Consequential choices expose the recommended outcome, what it preserves or gains, what it costs or risks, alternatives, and whether the decision can be reversed.
- Uses the party's lowest level to choose a concrete activity: gain local exploration/dialogue XP, clear a safe mini encounter, or commit to the next core challenge. It finishes the current regional phase before entering the Underdark, Grymforge, or Crèche; the player can still override it.
- Persists the party-wide act, character levels/builds, checklist state, completed/skipped fights, and map calibration locally.
- Keeps one custom character plus all six Act 1 origins in a persistent roster, with at most four active. Dead/departed changes require confirmation, cannot silently reactivate, and never imply a separate story reward.
- Tracks Act 1 equipment ownership per character in the separate **Loadout** tab. Unique items have one confirmed owner and transfer explicitly instead of appearing equipped twice.
- Persists party names, class composition, prepared spells/capabilities, optional skip notes, muted checkpoints, and a pinned guide version per run.
- Warns when the lowest party member is below the guide minimum, preparation is unchecked, or prerequisites remain.
- Shows enemies, legendary actions, failure conditions, preparation, important notes, irreversible decisions, and completion criteria.
- Never completes a checkpoint from vision; the player must confirm, skip, or revisit it.
- Requires an explicit override before completing with unchecked conditions or crossing an irreversible checkpoint; skipped major objectives remain visible in the Act 2 gate.
- Keeps automatic capture optional and off by default. **Visual Memory** samples one BG3 frame every 30 seconds, records a bounded evidence history, and offers likely completions for player review; **Map overlay** can reuse the same sample for local alignment.
- Registers Wilderness map artwork locally with ORB/RANSAC, then projects click-through markers through the recovered pan/zoom transform. Region bounds plus persisted calibration are the interior-map fallback.
- Keeps screenshots in memory. Only `DEBUG_CAPTURE=true` writes debug captures.
- Labels chat content as guide facts, assistant suggestions, or unknown information.
- Keeps the pet decision-first: next objective, minimum level, one run-ending risk, and Plan/Dialogue/Ask/Done. Full tactics, panic plans, completion checks, sources, and optional screen analysis stay collapsed until requested.
- Keeps the Twilight Cleric perfectly still at rest. Hovering the sprite plays its authored jump reaction and then uses all 16 v2 look directions to follow the pointer; leaving returns to the neutral frame without moving the overlay.
- Enforces one assistant instance per macOS user. Opening another copy—from the app bundle or an extracted ZIP—activates the existing assistant instead of creating a second pet or backend.
- Runs fully in **Vanilla** mode with no mod. An explicit, optional **Live Events** mode can read a bounded local event snapshot from the separately installed telemetry bridge; stale, absent, malformed, and incompatible feeds fall back to Vanilla without changing route progress.

## Install a release build

Requirements: Apple-silicon Mac, macOS 14+, and BG3 via Steam.

1. Unzip `BG3-Honor-Mode-Assistant-<version>-macOS-arm64.zip`.
2. Move **BG3 Honor Mode Assistant.app** to Applications and open it.
3. Screen Recording is not requested at startup. If you enable **Visual Memory** or **Map overlay**, or explicitly choose **Verify Capture Now** / **Check screen**, click **Continue** and approve **BG3 Honor Mode Assistant** in macOS. The app verifies real pixel access when you return; relaunch only if macOS explicitly requests it.

The release app starts its embedded local backend automatically. It does not require Python, `uv`, Swift, the source checkout, or an API key. `OPENROUTER_API_KEY` or `OPENAI_API_KEY` is optional and enables **Visual Memory** and explicit **Check screen** analysis; all deterministic planning and local map features work without either key.

## Source development

Requirements: macOS 14+, Swift 6, Python 3.11+, `uv`, and BG3 via Steam.

Start the development backend:

```sh
cd backend
cp ../.env.example .env
uv sync
uv run uvicorn app.main:app --host 127.0.0.1 --port 8787
```

`OPENROUTER_API_KEY` or `OPENAI_API_KEY` is optional for Visual Memory and screenshot analysis. Route, readiness, map data, and deterministic chat do not require either key.

Build and open the signed local app bundle:

```sh
cd mac
./scripts/build-app.sh
open -n "BG3 Honor Mode Assistant.app"
```

The build freezes and embeds the backend, copies the validated v2 pet from `~/.codex/pets/twilight-cleric/spritesheet.webp`, uses the permanent bundle ID `com.datamaki.BG3HonorAssistant`, and signs with the first local Developer ID, Apple Development, or ad-hoc identity it can use.

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

Automatic capture is disabled by default, so first launch does not request Screen Recording. When the player explicitly enables **Visual Memory** or **Map overlay**, or uses a manual capture action, the app shows one short explanation. Run the installed `/Applications/BG3 Honor Mode Assistant.app`, click **Continue**, then choose **Open System Settings** in the macOS dialog; the app row is created or refreshed after that system-owned step, not behind the unresolved dialog. Existing grants skip this explanation. While permission is unresolved, background work performs only the cheap preflight check—it never retries pixel capture or floods TCC. After leaving System Settings, the app performs one real pixel capture and otherwise shows a precise retry. If macOS explicitly requests a relaunch, use **Quit & Reopen**.

If an affected macOS 26 installation still does not create the row, click **+** in that pane and select **BG3 Honor Mode Assistant.app** manually. Install the app in Applications first; do not keep alternating between extracted, development, and release copies because TCC tracks the signed app identity and path.

Normal coaching and marker export require no screen access. Optional Visual Memory and map alignment use only screen pixels; `capturesAudio` and microphone capture are disabled in the screenshot pipeline. The macOS settings page combines screen and system-audio controls, but this app never records system audio. The app does not synthesize input. An explicit Computer Use session may place the exported markers in BG3; that operator has separate macOS control authority and must be limited to the open map's custom-marker flow—never combat, movement, dialogue, inventory, or other gameplay input.

## Vanilla and optional Live Events

**Vanilla is the default and complete experience.** Leave **Use optional Live Events** off to run the existing capture/manual companion with no BG3 mod dependency.

Live Events is an optional enhancement for players who knowingly accept a modded run. The separately packaged bridge publishes combat, down/death/revive, roll, level, equipment, and rest events to one local JSON snapshot. The backend validates it as untrusted advisory input; the native planner can show one concise event action, but never changes a character, build, checklist, route step, or completion state. If the feed is older than eight seconds, the app reports **Vanilla fallback** and continues normally.

The experimental source remains in [`mod/BG3HonorTelemetry`](mod/BG3HonorTelemetry) as deferred future work. It is intentionally excluded from default tests, validation, packaging, and release gates. Nothing in the main app installs, enables, or injects it.

## User flow

1. Open the app and click **Launch BG3** if the game is not already running.
2. The small pet appears when BG3 is detected. It remains still until hovered; move across the sprite to wake it and change its gaze. Drag the surrounding tooltip background to reposition the overlay.
3. Read its current phase, compressed readiness, next objective, and single highest-risk mistake. Use **Done** to archive the activity, **Plan** for the current activity and upcoming fight, **Talk** for the current or next consequential conversation, or **Ask** for contextual chat. Choose Minimal/Focus/Reference from the control window or pet menu; hold **Option-Space** to peek from Minimal. Screenshot checking is never required for progress.
4. In **Current**, scan **Do now**, **Don't die**, key Honor decisions, and **Prep**. Fight details, completion checks, sources, skip controls, and optional screen analysis are collapsed until requested. **Pin fight** returns to the combat card.
5. In native **Route** or the localhost **Walkthrough**, choose **Focus this** on any unresolved activity when the open world takes you somewhere other than the recommendation. Done/Skipped work leaves the active route immediately and stays recoverable under **Archive → Revisit**. After a fight, confirm the compact **Recover** checklist before continuing. Expand decision tradeoffs or panic plans only when needed.
6. In **Party**, set the active party level, promote or bench companions, and assign reviewed builds across the full roster. Each card shows only the current-level action—never a next-level teaser. Use the separate **Loadout** tab for act-scoped equipment, confirmed ownership, acquisition locations, and map actions. Assigning a build assumes its reviewed setup; class/capability deviations stay under **Advanced**. The control window's **Party Loadout** button opens Loadout directly.
7. In **Chat**, ask what is next, which dialogue choice to make, how to avoid dying, or whether the party is ready. Optionally enable **Visual Memory** in the control window to analyze one BG3 frame every 30 seconds. Observations are deduplicated and retained locally; a likely completion opens the matching step for review, and only the player's **Done** confirmation changes progress. **Check screen** remains an explicit one-off action.
8. In the localhost map, choose **Export BG3 markers**. The queue is derived from the selected act, lowest party level, assigned builds, completed fights, and equipped gear. Opening the preview temporarily sends those exact labels to the in-game click-through overlay and can also download the versioned JSON manifest.
9. If desired, enable **Map overlay** and open the BG3 map. The local matcher reuses the optional 30-second sample to align the active queue; it does not run a separate fast screenshot loop. A Computer Use session can then create only those named custom markers. After screenshot verification, click **Placed in BG3**; the fingerprint is persisted, repeat exports show `Already placed`, and the temporary overlay clears.
10. The Act 2 gate remains visible throughout the planner. Resolve displayed pending or skipped major/irreversible objectives before advancing.

## Local Act 1 browser map

The backend serves a fast companion walkthrough and map at [http://127.0.0.1:8787/map](http://127.0.0.1:8787/map). **Walkthrough** is the default view: it groups 59 player-confirmed steps into 11 regional phases, recommends the closest safe incomplete step for the party's level, and interleaves 15 dialogue/decision challenges with exploration and fights. High-value steps expose a compact `POWER` line for the equipment, permanent bonus, or summon at stake. Players may focus any unresolved step; the recommendation stays available as an alternative. Resolved steps are removed from phase lists and retained in the collapsed Archive. Fight completion pauses on a Recover card before guidance advances. Decision tradeoffs, incident protocols, Honor deltas, and optional risk/reward stay collapsed until requested. **Map** uses MapGenie's Wilderness raster tiles with attribution and overlays guide fights plus Act 1 build equipment. Completed fights and acquired items are archived from the visible map by default. The app does not copy or impersonate the MapGenie website; **Open MapGenie Wilderness** links to the original service.

The map supports region, level, build, type, completion, label, and search filters. Its **Party** tab preserves all four character names, individual levels, and selected builds from the native companion and shows only each character's current-level action. **Equipment** is a separate, act-scoped tab grouped by party member; assignments persist independently per character and every item can be opened on the map. Every reviewed build must provide a current Act 1 interim loadout even when its defining equipment arrives later; Flamadin currently has 11 Act 1 recommendations and Control Martial has 14. Exact and area-level pins are visually distinguished so coarse item sources do not claim false precision. Marker export is phase-aware: it includes safe unresolved fights in the current route region and unequipped equipment for the selected builds. Fight levels remain guide facts; equipment labels use the selected party level and are identified as assistant suggestions.

## Verification

```sh
cd backend && uv run --with pytest python -m pytest -q
cd ../mac
swiftc BG3Assistant/BG3Models.swift BG3Assistant/BG3Detector.swift BG3Assistant/MapOpenDetector.swift BG3Assistant/RunStore.swift BG3Assistant/OverlayMetrics.swift BG3Assistant/PetAnimationModel.swift BG3Assistant/BackendProcessManager.swift BG3Assistant/PermissionManager.swift ModelTests/main.swift -lsqlite3 -o /tmp/bg3-model-tests
/tmp/bg3-model-tests
swift build
./scripts/build-app.sh
./scripts/build-release.sh
```

See [`COMPLETION_AUDIT.md`](COMPLETION_AUDIT.md) for requirement-by-requirement evidence and the remaining packaged map-overlay check.

## Data and grounding

- `data/act1_fights.json`: source fight facts and world coordinates.
- `data/act1_route.json`: reviewed order, prerequisites, danger, failure conditions, and gates.
- `data/act1_walkthrough.json`: reviewed regional walkthrough steps, player-facing completion checks, source authority, and explicit decision tradeoffs linked back to fight checkpoints and map markers.
- `data/build_overview.tsv`, `build_levels.tsv`, `build_gear.tsv`: reviewed build and equipment data. Build entries are presented as ideas unless their level plan has been reviewed.
- `mod/BG3HonorTelemetry`: deferred experimental source; not part of current tests, validation, packaging, or release gates.
- Runs, the active-run pointer, the latest 20 revisions per run, and assistant settings: `~/Library/Application Support/BG3HonorAssistant/state.sqlite3`.
- Legacy `run.json` is imported once when no SQLite run exists; it is retained as a migration backup and is no longer a live state authority.
- Embedded-backend state and logs: `~/Library/Application Support/BG3HonorAssistant/backend` and `~/Library/Application Support/BG3HonorAssistant/debug`.
- The run's guide version is pinned. A newer backend guide is reported but does not silently rewrite an active run.

Primary fight source: [BG3 Honor Mode guide](https://docs.google.com/spreadsheets/d/1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0). Map reference: [MapGenie Wilderness](https://mapgenie.io/baldurs-gate-3/maps/wilderness).

## Limitations

- When Map overlay is enabled, Wilderness alignment is automatic because the in-game map and reference mosaic share artwork; synthetic tests cover 0.55×–3.5× zoom. Alignment refreshes on the shared 30-second cadence rather than continuously. Interior regions use coordinate bounds and may need manual calibration because they are not on the Wilderness mosaic.
- Live BG3 process detection, real-window capture, live non-map rejection, and positive registration of a real 2560×1440 Wilderness map are verified. The fixed packaged marker panel still needs one visible pan/zoom alignment observation in the game.
- Map registration requires the local MapGenie tile cache to be available. OCR plus saved region calibration is the offline fallback.
- Fast OCR depends on recognizable English map labels. The overlay hides when the detector is not confident.
- True exclusive fullscreen can place macOS panels behind the game; use windowed or borderless fullscreen.
- BG3 may be discovered across macOS Spaces, but a fully minimized or unavailable Metal window cannot be captured until it is restored.
- Live Events/mod work is deferred and does not participate in the current release loop.
- No game-memory reading, mods, save editing, combat automation, or general gameplay input control. Visual Memory is an explicit, default-off 30-second screenshot analysis feature—not a continuous stream—and never completes progress without player confirmation. The native app never synthesizes input; an external, explicit Computer Use session may operate only the open BG3 custom-marker flow from the exported manifest.
- The current local `0.1.0` artifact is Apple Development-signed and therefore not a public Gatekeeper-ready download. Public distribution is blocked only on the publisher's Developer ID certificate, final bundle ID, and notarization profile; the release script enforces those when `REQUIRE_RELEASE_SIGNING=1`.
