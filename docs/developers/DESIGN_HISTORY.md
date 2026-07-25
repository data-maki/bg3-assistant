# Product and design history

This document explains why BG3 Overlay works the way it does. It is the short version of the product discussions, design experiments, and implementation decisions recorded across the repository history.

For the current implementation details, read [ARCHITECTURE.md](ARCHITECTURE.md). For contribution rules, read [CONTRIBUTING.md](../../CONTRIBUTING.md).

## Contributor summary

BG3 Overlay began as an Honor Mode safety companion for one problem: players were repeatedly leaving Baldur's Gate 3 to check routes, builds, gear, and warnings. The product later broadened to Balanced and Tactician runs, but the core interaction stayed the same:

1. Show the next useful action.
2. Surface the one mistake that could close content or ruin a run.
3. Keep deeper route, party, build, and equipment detail one click away.
4. Treat reviewed guide data and deterministic rules as authoritative.
5. Let AI explain context, but never let AI silently rewrite guide facts or player progress.

The app is intentionally an overlay rather than a mod. It does not load into the BG3 process. It runs as a separate native macOS application and places a transparent, always-on-top panel beside the detected game window.

## Original guidelines

The first product design was written for Honor Mode Act 1. It prioritized three questions: **What is next? What can ruin the run here? How should the party prepare?**

That led to the following guidelines:

- **The route is the source of truth.** An LLM can summarize or explain a route entry, but it is not the progression engine.
- **Player confirmation owns progress.** Detection can provide evidence or a suggestion; completing, skipping, or resolving an event changes the run only after confirmation.
- **The collapsed view is one decision, not a dashboard.** The pet and peek card show the next objective, one warning, and a few direct actions. The full planner holds everything else.
- **High-stakes advice should be conservative.** Missing or uncertain information is labelled unknown instead of being invented.
- **The game remains untouched.** The released app does not edit game files, read saves or memory, automate input, or require a mod loader.

The visual direction followed the same restraint: translucent umber surfaces, parchment text, bronze and gold framing, compact serif headings, and red reserved for dangerous states. The goal was to feel at home beside BG3 without recreating the game UI wholesale. The later manual builder added sourced spell, feat, and ability icons under the project's fan-content attribution because those images materially improve recognition during level-up decisions.

## How the app became an overlay

“In-game overlay” describes placement, not process integration.

```text
┌────────────────────── Baldur's Gate 3 ──────────────────────┐
│                                                             │
│  BG3 process and window                                     │
│        │                                                    │
│        │ detected frame only                                │
│        v                                                    │
│  ┌────────────── separate BG3 Overlay process ────────────┐ │
│  │ MenuBarExtra → AppState → OverlayPanelController       │ │
│  │                              │                          │ │
│  │                              v                          │ │
│  │               borderless, transparent NSPanel          │ │
│  │               pet → peek card → full planner           │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

Guide bundle ──read-only──> AppState <──read/write── state.sqlite3
                                  └──optional──> local AI or OpenRouter
```

The native app has no normal `WindowGroup`. A menu-bar item owns the lifecycle, and `BG3Detector` finds the running game and its window bounds. `OverlayPanelController` hosts SwiftUI inside a borderless AppKit `NSPanel` that:

- stays above the game and can join fullscreen Spaces;
- saves its position as a normalized anchor relative to the game window;
- resizes between the pet, peek card, onboarding, and planner states;
- avoids taking focus from BG3 for ordinary controls;
- becomes key only when the player clicks a text field or another input that needs typing.

Every surface reads the same `AppState` and persisted run. The pet, **Now**, **Route**, **Party**, **Loadout**, **Act**, and **Chat** are different projections of one run rather than separate mini-apps with their own state.

The release runtime is native Swift. Reviewed route and build data is compiled into `guide-bundle.json` before release. Python remains useful for validating and generating that bundle, but the installed app does not start FastAPI or a project-hosted companion server.

## Evolution through the commit history

### 1. Honor Mode prototype and deterministic route

[`ce774ff`](https://github.com/data-maki/bg3-assistant/commit/ce774ff) established the Act 1 assistant, route data, map experiments, native macOS shell, and the first written product design. The important choice was to ground the product in reviewed checkpoints and preparation rules instead of building a general floating chatbot.

The earliest work also explored map alignment, OCR, screenshot understanding, and game telemetry. These were useful experiments, but they were broader and more invasive than the final product boundary.

### 2. Glance-first party, chat, and planner

[`b824e7c`](https://github.com/data-maki/bg3-assistant/commit/b824e7c) added guide-grounded chat, the walkthrough ledger, Party/Route/Loadout/Chat surfaces, persistence, and an early global peek interaction. The accompanying Party design made a durable UI choice: show the current level decision for each character first, then disclose full progression and equipment.

This phase briefly included a telemetry mod. It proved that deeper game integration was possible, but it also increased installation, trust, maintenance, and compatibility costs.

### 3. Standalone overlay boundary

[`69f7dbe`](https://github.com/data-maki/bg3-assistant/commit/69f7dbe) removed the mod and telemetry path and shipped the standalone overlay. It also added the MIT license, contribution templates, player-facing documentation, explicit capture controls, and a clearer split between native UI and supporting data tools.

This is the product boundary contributors should assume today: **no mod connection is required or expected**.

### 4. Compact HUD and BG3-aligned presentation

[`07da5e9`](https://github.com/data-maki/bg3-assistant/commit/07da5e9) simplified the expanded overlay, introduced the compact encounter HUD, and added the current branding. The app moved away from showing every possible control at once and toward a smaller pet/peek surface that expands only when needed.

This commit also reinforced a practical overlay constraint: the assistant should avoid the minimap and hotbar, stay readable at a glance, and retain the player's chosen position.

### 5. Multi-act planner and one shared run model

The data and catalog sequence beginning with [`c5276b8`](https://github.com/data-maki/bg3-assistant/commit/c5276b8) and culminating in [`e9878a3`](https://github.com/data-maki/bg3-assistant/commit/e9878a3) added:

- Act 2 and Act 3 guide inputs;
- structured build, item, gear, and ability data;
- deterministic equipment contention and manual overrides;
- a roster-first Party flow and act-aware Loadout;
- route dependency checks, immutable act transitions, build import, and first-run onboarding;
- feature-oriented `AppState` extensions around one persisted `HonorRun`.

The key architectural choice was consistency: the UI, route safety rules, party state, equipment ownership, and chat context should all reference the same stable guide and run identifiers.

### 6. Hardening, simplification, and open-source onboarding

[`5b2d1da`](https://github.com/data-maki/bg3-assistant/commit/5b2d1da) hardened onboarding and all-act behavior. [`8142c4c`](https://github.com/data-maki/bg3-assistant/commit/8142c4c) removed the unused Option-Space path and other dead state. [`085f4ce`](https://github.com/data-maki/bg3-assistant/commit/085f4ce) removed historical working documents and tests that only repeated implementation details. [`a2fca56`](https://github.com/data-maki/bg3-assistant/commit/a2fca56) documented the runtime and state authority in depth.

Finally, [`bfa7763`](https://github.com/data-maki/bg3-assistant/commit/bfa7763) made installation and contribution easier to understand, and [`07da13d`](https://github.com/data-maki/bg3-assistant/commit/07da13d) introduced explicit local Gemma, local Qwen, and OpenRouter choices. AI became optional infrastructure around the planner, not a requirement for using it.

## Current direction

The current implementation broadens the name from “BG3 Honor Mode Assistant” to **BG3 Overlay** while keeping the risk-aware design.

- Onboarding asks whether the player is starting fresh or joining mid-run.
- The supported overlay difficulties are Balanced, Tactician, and Honour Mode. Explorer is directed toward enjoying the game without a checklist, and Custom is not offered because its rule variants cannot be modelled reliably.
- Players choose between the full act plan and only three tasks ahead. Equipment challenges remain visible in either mode.
- Party members can use reviewed builds, imported builds, or a manual level 1–12 planner.
- Manual leveling continues the current class by default. A separate **Multiclass** action changes that level and its inherited future levels.
- Spells, cantrips, feats, subclasses, and class features use bundled option artwork with an offline fallback and attribution manifest.

These additions preserve the original hierarchy: immediate action first, complete planning detail on demand.

## Design rules for new contributions

Use these as review questions:

1. Does the change make the next player decision clearer?
2. Is a fact coming from reviewed data, a deterministic rule, player-confirmed state, or AI inference—and is that distinction visible?
3. Can the feature remain useful without AI or network access?
4. Does the collapsed overlay remain small and non-disruptive?
5. Does any new detection propose a change rather than silently mutating the run?

A deliberate product proposal can change these rules, but it should name the trade-off and update this document, [ARCHITECTURE.md](ARCHITECTURE.md), and [CONTRIBUTING.md](../../CONTRIBUTING.md) together.

## Improvement opportunities

### Near-term improvements

1. **Complete Act 2 route coverage.** Act 2 currently has equipment and map support but not an app-ready reviewed route. Finishing its prerequisites, timed events, outcome branches, and transition checks would make the three-act experience continuous.
2. **Strengthen manual-build legality and patch versioning.** Validate spell availability, prerequisites, feat timing, multiclass requirements, prepared-versus-known spell rules, and Patch-specific class changes. Keep source dates and patch numbers visible so contributors can update one catalog without silently changing old runs.
3. **Make content contribution easier.** Add schemas, focused validation commands, source templates, and a generated contributor report for routes, equipment, class options, images, and citations. A contributor should be able to see exactly which act or class is incomplete before opening a pull request.

### Larger product and architecture bets

4. **Port the overlay to Windows.** Share the guide bundle, run schema, deterministic rules, and golden behavior tests. Replace the macOS shell with a Windows host using a transparent topmost WinUI/WPF window, Win32 game-window detection, Windows Graphics Capture, Credential Manager, and SQLite. The simplest reliable path is to share data contracts and tests first, then reproduce only the platform presentation and OS services instead of trying to cross-compile SwiftUI.
5. **Add an opt-in screenshot observation loop.** Capture the BG3 window only while the game is foregrounded, deduplicate unchanged frames locally, and convert useful changes into structured observations. Detected events should create a completion suggestion—not complete the event automatically:

   ```text
   BG3 window
       │ opt-in capture cadence
       v
   local crop + frame deduplication
       │
       v
   OCR / local vision / explicit cloud vision
       │
       v
   structured observation memory
   {area, event candidate, evidence, confidence, guide IDs, time}
       │
       v
   "Looks like you completed Save Mirkon"
   [Confirm completion] [Not yet] [Ignore this event]
       │
       └── Confirm uses the existing progress mutation and safety checks
   ```

   Raw screenshots should remain in memory and expire by default. Persist only confirmed facts and a bounded observation log with provenance. The overlay needs a visible capture indicator, pause control, configurable cadence, per-provider disclosure, and an option that guarantees local-only processing. This feature would intentionally revise the current one-shot-capture boundary, so privacy copy, permissions, resource usage, and false-positive recovery are part of the feature rather than follow-up work.
6. **Reduce platform coupling in the state coordinator.** `AppState` is already split by feature, but it still coordinates lifecycle, overlay navigation, guide loading, persistence, party editing, capture, and AI. Extract more pure run transitions and provider-independent observation rules into a tested core. This would make the Windows port, screenshot-event suggestions, and background task cancellation easier to implement without duplicating behavior.

## Where contributors should start

| Change | Primary location |
| --- | --- |
| Overlay behavior or presentation | `mac/BG3Assistant/Overlay*.swift` and the relevant `*TabView.swift` |
| Run, route, party, or build behavior | `mac/BG3Assistant/BG3Models.swift`, `AppState+*.swift`, and pure rule files |
| Manual leveling and option artwork | `ManualBuild.swift`, `ManualBuildPlannerView.swift`, and `Resources/BuildOptionIcons` |
| Reviewed route, build, or equipment facts | `data/` plus the bundle generator |
| Packaging and validation | `scripts/macos/` and `docs/developers/RELEASE.md` |

Run `./scripts/macos/validate.sh` before submitting native changes. If `data/` or Python loaders changed, regenerate the guide bundle and run the backend tests as described in [CONTRIBUTING.md](../../CONTRIBUTING.md).
