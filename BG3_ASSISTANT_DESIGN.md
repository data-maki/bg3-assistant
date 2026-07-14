# BG3 Honor Mode Assistant — Act 1 Product Design

## Recommendation

Build a deterministic Act 1 route companion with a pet as its smallest UI, then add screenshot understanding and guide-grounded chat around that route.

The assistant should not behave like a general BG3 chatbot that happens to float over the game. Honor Mode players need three things at the exact moment they matter:

1. **What is next?** A safe, ordered route with prerequisites and level gates.
2. **What can ruin this run here?** Time-sensitive, irreversible, and legendary-action warnings.
3. **How do I prepare?** A short pre-fight checklist tailored to the player's party and chosen builds.

The route is the source of truth. Vision suggests where the player is and what is visible; the player confirms progress. Chat explains the current checkpoint using the guide and saved run state.

Competitive-overlay research reinforces that the pet should become phase-aware rather than grow into a dashboard. See [`COMPETITIVE_OVERLAY_RESEARCH.md`](COMPETITIVE_OVERLAY_RESEARCH.md) for the Hearthstone, Valorant, Dota, and League comparison and the recommended `explore → preflight → dialogue/combat → recover` interaction model.

The implemented route model separates three concepts that must never be conflated:

```text
Reviewed recommendation ──┐
Player-selected focus ─────┼──> current phase card
Manual Done/Skip ledger ───┘          |
                                      +──> Archive -> Revisit
```

The recommendation is always recoverable, but never forces the player's open-world choice. Only unresolved work is active; resolved work is archived rather than faded in place.

## Architecture options

### Option A — Checklist-only overlay (simplest)

```text
Google Sheet -> Curated Act 1 JSON -> macOS overlay -> player checks items
```

This is fast and dependable. It cannot recognize where the player is, tailor advice to the current screen, or answer contextual questions well.

### Option B — Hybrid route engine + vision + chat (best)

```text
Curated guide data -----------+
Player run/party state -------+--> Route engine --> Pet + planner
Optional 30-second capture ----+         |
  |-- visual evidence memory --+         |
  +-- local map alignment -----+         |
                                         +--> Grounded chat
```

This keeps high-stakes guidance deterministic while letting the assistant recognize likely context, warn about visible danger, and answer questions. This is the recommended architecture.

Do not make an LLM the progression engine. It may summarize or explain guide data, but it must not invent prerequisites, mark objectives complete, or silently move the player to another checkpoint.

## Core interaction model

### 1. Pet — always available, nearly invisible

The pet sits near a screen edge above BG3 in windowed/borderless fullscreen. It has four useful states:

- **Idle:** a neutral, completely still frame. The pet must not animate autonomously over gameplay.
- **Next:** a small route marker appears when a next step is ready.
- **Caution:** amber marker for a level/preparation mismatch.
- **Danger:** red marker for an imminent irreversible or run-ending risk.

The pet should never narrate continuously or cover combat UI. A single click opens the planner. A right-click or small quick-action opens chat directly. The user can drag it, mute it, or snooze warnings.

Pet motion is user-invoked and follows the Codex v2 atlas contract. Hovering directly over the sprite plays one authored jump reaction using the row's native timing, then the pet follows the pointer with the 16 clockwise look cells. Leaving the sprite immediately restores the neutral frame. The animation changes only sprite frames; it never moves the overlay window. Reduce Motion skips the jump and keeps only direct gaze feedback.

The expanded planner is one system glass surface, not a stack of custom cards. Native material remains the behavioral foundation, but its visual vocabulary should belong beside BG3: translucent umber rather than cool gray, a restrained bronze/gold double hairline, parchment text, compact serif display headings, and red used only for lethal state. Do not copy or redistribute BG3 artwork. Standard inputs remain native; navigation chrome may use a lightweight game-aligned treatment where a stock segmented control visibly clashes. Header and navigation chrome stay intrinsic-height, and the planner uses tab-specific content envelopes rather than a single oversized fixed frame.

The collapsed state is a horizontal tooltip, not a portrait dashboard. It defaults to the middle-right edge, grows inward when expanded, and leaves the top-right minimap and bottom hotbar bands clear. It retains the full interaction contract—next walkthrough step, level/danger, one `AVOID`, and Plan/Dialogue/Ask/Done—in roughly one tooltip-sized glance.

### 2. Peek card — one decision, not a dashboard

```text
                                      ┌─ BG3 screen ─────────────────────┐
                                      │                                  │
                                      │                    ┌───────────┐ │
                                      │                    │  pet  (!) │ │
                                      │                    └───────────┘ │
                                      │              click ->            │
                                      │       ┌────────────────────────┐ │
                                      │       │ NEXT: Harpy beach      │ │
                                      │       │ Reach level 4 first     │ │
                                      │       │ ! Save Mirkon           │ │
                                      │       │ [Plan] [Dialogue]      │ │
                                      │       │ [Ask]  [Done]          │ │
                                      │       └────────────────────────┘ │
                                      └──────────────────────────────────┘
```

The peek card shows only:

- current or next checkpoint;
- minimum/recommended level status;
- the single most important warning;
- `Plan`, `Dialogue`, `Ask`, and `Done` actions. Dialogue opens the current or upcoming conversation protocol without removing it from the unified route.

### 3. Planner — the main assistant surface

```text
┌─ ACT 1 · Harpy Beach ──────────────────────────┐
│ Route  03 / 18                     Level 3  ⚠  │
│                                                │
│ BEFORE YOU GO                                  │
│ ☐ Reach level 4                                │
│ ☐ Prepare Calm Emotions or Silence             │
│ ☐ Prepare Sanctuary for Mirkon                 │
│                                                │
│ FIGHT                                          │
│ 4 harpies · WIS lure · protect Mirkon          │
│                                                │
│ AFTER                                          │
│ ☐ Confirm Mirkon survived                      │
│                                                │
│ [Show route] [Party/builds] [Ask about this]   │
└────────────────────────────────────────────────┘
```

Tabs:

- **Current:** checkpoint briefing and checklists.
- **Route:** Act 1 timeline, filters, completed/skipped state, and alternate branches.
- **Party:** one custom-character slot plus three selectable Act 1 story companions, with immediate per-character level/build controls and current/next build steps. Class overrides, capability deviations, full progression, and gear stay behind disclosure.
- **Chat:** automatically grounded in the current checkpoint, guide excerpts, party state, and latest optional screenshot.

## Assistance by moment

### Exploration

- Show the next destination as a named area and landmark description, not an unreliable invented map pin.
- Surface prerequisites before the player crosses a boundary or starts a timed quest.
- Keep a short pickup/talk-to list for the current area.
- Warn before long rests only when the guide identifies a real time-sensitive condition.

Examples from the source guide:

- Grove: bugbear assassination, Rolan, Alfira for Dark Urge, Mirkon, Kagha/idol ordering.
- Waukeen's Rest: save Florrick and Benryn/dowry objectives before leaving.
- Grymforge: Nere becomes timed on entry; visit Philomeen first.
- Mountain Pass: do not enter before resolving applicable Act 1 objectives.

### Before a fight

Show a five-part preflight:

1. **Level gate** — guide minimum where provided; otherwise explicitly `not specified by guide`.
2. **Failure conditions** — NPC deaths, chasms/lava, surprise, control effects.
3. **Legendary action** — short plain-language explanation and trigger.
4. **Preparation** — spells, consumables, positioning, and escape plan.
5. **Completion condition** — important bargains, non-lethal outcomes, or rewards.

High-value permanent powers and equipment chains are first-class steps rather than prose buried inside an area: permanent Shovel, the Necromancy of Thay reader decision, Mourning Frost components, the one-choice Sussur forge, and the Blood of Lathander crest path. The compact card exposes only a `POWER` line; ownership, tradeoffs, and exact completion proof remain behind the step detail.

The player can press `Ready` to pin a combat-sized version of the card.

### In combat

The assistant should be conservative. It can show the pinned plan and answer on demand, but it should not continuously call vision or bark tactical commands. Honor Mode combat changes too quickly, and a stale instruction is worse than silence.

Useful pinned content:

- boss legendary trigger;
- kill/disable priority;
- environmental hazard;
- one fallback/escape reminder;
- protected NPC or special completion condition.

### Level-up and party preparation

The spreadsheet's `Great builds` tab contains end-state class splits and some key feats, not complete level-by-level plans. Therefore:

- represent those entries as **build ideas sourced from the guide**;
- add separately curated, versioned level-by-level plans before claiming to recommend each level;
- let the player assign a plan to each party member;
- show only the next choice: class, subclass, feat/ASI, spells, invocation, fighting style, and key gear goal;
- compare the planned party against the next fight's needs, e.g. silence, Calm Emotions, fire, bludgeoning, high initiative, or control.

Never recommend a respec or consumable without showing why it matters for the next checkpoint.

Before implementation, create separate detailed plans for the requested Swords Bard Archer, Shadow Blade user, Light Cleric, Open Hand Monk, Lockadin, Smite Swords Bard, Control Martial Bard, and Fire Sorlock references. Each plan must include level 1–12 choices, respec timing, ability priorities, feats, spells/features, combat loop, equipment by slot, acquisition Act and named location, important alternatives, and the original source URL. Similar bard variants remain separate selectable plans.

### Chat

Clicking the pet opens chat with a context header such as:

`Act 1 · Owlbear Cave · Level 4 party · checkpoint not completed`

Fast prompts:

- `What can end my run here?`
- `Am I ready?`
- `Where do I go next?`
- `What should I prepare?`
- `What do I take at this level?`
- `Can I long rest safely?`

Every answer should distinguish:

- **Guide says** — directly sourced route/fight advice.
- **Assistant suggestion** — derived from party/screen context.
- **Unknown** — not in the guide or not confidently visible.

## Act 1 content model

The fight sheet currently provides these main checkpoint groups, in sheet order:

1. Nautiloid/tutorial
2. Grove entrance
3. Harpy beach
4. Whispering Depths / Spider Matriarch
5. Owlbear Cave
6. Blighted Village
7. Goblin Camp bosses
8. Swamp redcaps
9. Swamp tree / wood woads and mephits
10. Auntie Ethel
11. Risen Road gnolls
12. Underdark Selunite Outpost / minotaurs and bulette
13. Underdark Spectator
14. Arcane Tower / Bernard
15. Sussur Tree / hook horrors and Filro
16. Grymforge / Nere
17. Adamantine Forge / Grym
18. Githyanki patrol
19. Gith crèche / W'wargaz

This ordering is a starting route, not yet a fully validated optimal sequence. The content importer should preserve source order and source text, while a reviewed route layer supplies prerequisites, optional branches, and recommended ordering.

Suggested data shape:

```json
{
  "id": "act1_harpy_beach",
  "act": 1,
  "area": "Grove — Secluded Cove",
  "kind": "fight",
  "sourceOrder": 3,
  "minimumLevel": 4,
  "danger": "high",
  "enemies": ["4 harpies"],
  "failureConditions": ["Mirkon dies", "party members are lured"],
  "legendaryAction": null,
  "prep": ["Calm Emotions", "Silence near Mirkon", "Sanctuary"],
  "prerequisites": [],
  "completionChecks": ["Mirkon survived"],
  "source": { "sheet": "Act 1 - fights", "row": 4 }
}
```

Store source facts separately from reviewed route metadata so the spreadsheet can be re-imported without overwriting product decisions.

## Screen understanding and map overlay

### Preferred workflow: one-shot BG3 custom-marker sync

The durable navigation surface should be BG3's own named custom markers, not a continuously projected assistant layer. The player explicitly exports a queue for the current act, party level, selected builds, equipped gear, and incomplete route state. Opening the preview activates those exact labels in the temporary click-through overlay and produces a versioned JSON manifest. An explicit Computer Use session—not the native app—places only those markers in BG3. Screenshot verification precedes manual confirmation of the fingerprint. A confirmed fingerprint must not reactivate until the queue changes or the player explicitly requests a new export.

```text
party act + level + builds + route state
                   |
                   v
          deterministic export queue
                   |
             explicit Export action
                   |
                   v
 temporary local alignment overlay -> Computer Use places markers
                   |
                   v
 screenshot verification -> player confirms fingerprint
```

This is a narrow, external input-automation exception. The native companion keeps only Screen Recording permission and never synthesizes clicks or keystrokes. A Computer Use operator may act only inside the open BG3 custom-marker flow and must stop on lost map confidence, unexpected UI, dialogue, combat, movement, inventory, or any non-map surface. Screenshot sampling remains local and in-memory; no continuous cloud computer-use or LLM vision is allowed.

### Local Act 1 companion map

The first functional map surface is a localhost web app served by the existing backend and launchable from the macOS control window. It owns our guide data and provides filters for minor XP fights, major route goals, and equipment by build. MapGenie's Wilderness map is a live external reference and handoff target; do not clone or redistribute its proprietary application or map assets.

The map keeps two party jobs separate. **Party** shows one current-level action per named character using that member's own level and reviewed build. **Equipment** shows only the selected act's gear, grouped and checked independently per character, with item-to-map handoff. Native party state is authoritative; the web run state persists the same member IDs so shared build items do not collapse into an anonymous global checklist.

A selectable reviewed build must have a complete current-act fallback loadout independent of its final best-in-slot list. For Act 1 this means reviewed recommendations and acquisition locations for head, chest, hands, feet, amulet, rings, ranged, and any build-defining main/off-hand setup. Later-act core pieces remain upgrades in their own act; they cannot leave the current-act Equipment view empty.

The local map must work without MapGenie being embedded. Each marker stores BG3 world coordinates, region, minimum recommended level, encounter/item type, build IDs, and source. Wilderness markers are plotted on a coordinate grid now; later map-image calibration can replace the neutral background without changing the data model.

Automatic capture is optional, persisted, and disabled by default. When the player enables **Visual Memory**, the app samples one BG3 frame approximately every 30 seconds and sends only that frame to the configured screenshot-analysis provider. When the player enables **Map overlay**, the same sample is reused by the lightweight local map matcher. Enabling both features must still produce one capture, not parallel loops.

When the map is detected, the app overlays the current route destination and relevant nearby guide locations using stored world coordinates. Coordinate records must identify the map/region they belong to because Act 1 includes separate surfaces such as the Wilderness, Underdark, Grymforge, and Mountain Pass. The overlay must calibrate world coordinates to screen pixels from stable map bounds or anchors; hard-coded screen pixels are not acceptable because resolution, UI scale, zoom, and panning vary.

**Implemented calibration (2026-07-12).** The in-game map and MapGenie's Wilderness tiles use matching artwork, so the backend registers each map screenshot against a locally cached z12 tile mosaic with ORB feature matching and a RANSAC similarity fit (`backend/app/map_align.py`, `POST /api/map-align`). Synthetic screenshot tests verify recovered transforms and target projection at 0.55×–3.5× zoom, and a live non-map BG3 capture verifies false-positive rejection. A positive live BG3 map-frame check still requires the player to open a loaded-save map. The matcher runs locally with no LLM call, and its inlier count is the authoritative map-open detector; the OCR classifier remains as a fallback when the backend is down. A successful alignment also publishes an approximate live player position (the aligned view centre) to `GET/POST /api/position`, which the companion web map polls to render a beacon with follow mode. Guide markers carry MapGenie lat/lng resolved from MapGenie's location data, so the companion map, overlay, and alignment mosaic share one coordinate system. Tiles are hot-linked or cached at runtime (`backend/runs/map_cache/`, gitignored) — MapGenie assets are not redistributed.

```text
BG3 window screenshot (optional, 30 sec)
          |
          +------------------------------+
          |                              |
          v                              v
Visual Memory analysis          POST /api/map-align
evidence + completion hints      local ORB match vs mosaic
          |                              |
          v                       inliers >= 20?
Player reviews -> Done                    |
changes progress                         yes
                                         v
                             transform -> markers + position
```

The evidence ledger is bounded, timestamped, and deduplicated. It may remember the likely activity, visible context, and directly evidenced completion candidates. A completion hint opens the matching step for review; it never changes the walkthrough ledger itself. Location alone, an empty battlefield, or simply appearing later in the route is not completion evidence.

The local map path remains:

```text
POST /api/map-align (local ORB match vs MapGenie mosaic)
          |
   inliers >= 20? ---- no ----> hide overlay (map closed)
          |
         yes
          v
similarity transform -> targets in screen px + player position
          |                               |
          v                               v
Transparent click-through markers   /api/position -> web map beacon
```

Screenshot analysis runs either through the explicit `Check screen` action or the opt-in 30-second Visual Memory schedule. It should try to identify:

- likely area or encounter;
- combat vs exploration vs dialogue vs level-up screen;
- visible enemies and status effects;
- party level and visible party members where legible;
- active dialogue choice or warning;
- confidence and evidence.

It should return checkpoint candidates, not a definitive location. If confidence is low, ask the player to choose from two or three nearby route points. It may log a completion candidate only when direct visible evidence matches the reviewed completion check. A screenshot must never automatically complete an objective.

No capture schedule runs by default. The only automatic schedule is the explicit 30-second Visual Memory/Map overlay preference. Screenshots remain in memory unless debug capture is explicitly enabled; the persisted visual memory stores compact text evidence, not image bytes.

Screen-capture permission uses a three-signal model: raw `CGPreflightScreenCaptureAccess`, an explicit TCC request from the consent sheet, and a successful real pixel capture. `SCShareableContent` metadata enumeration is never authorization. The signed app includes `NSScreenCaptureUsageDescription` and a permanent bundle ID. Startup does not request permission while capture features are off; enabling a feature or choosing a manual capture action presents the explanation, whose Continue button invokes the system request synchronously. Existing grants never see that prompt. Background refreshes only recheck, generic stream failures are reconciled with a tiny local screenshot, and `capturesAudio`/microphone capture remain disabled.

## Progress and safety model

- Progress is local-first and per run.
- The player explicitly checks completion or accepts a suggested completion.
- `Skip` requires an optional note and remains visible in route history.
- Irreversible decisions require a confirmation step.
- The assistant stores party/build state separately from route progress.
- The guide version is pinned to each run so updates do not silently change an active playthrough.
- Advice can be muted by checkpoint or category.

## What to reuse from the original prototype

Reuse:

- native SwiftUI/AppKit macOS app;
- floating non-activating `NSPanel` behavior;
- BG3 process/window detection pattern;
- ScreenCaptureKit capture and overlay-hiding flow;
- local FastAPI process and health checks;
- debug logging and opt-in screenshot analysis.

Replace:

- legacy detector names and Steam launch target;
- red `Ask` button with the pet and peek card;
- legacy screen schema/prompt;
- turn recording and turn-log overlay;
- generic spoken screen summary as the primary output;
- legacy strategy-game models with route, party, encounter, and progress models.

## MVP scope

### Phase 1 — useful without AI

- Rebrand app and detect/launch BG3.
- Pet overlay with idle/caution/danger states.
- Curated Act 1 route and fight cards from `Act 1 - fights` and `Act 1 - Notes`.
- Manual run progress and party level/class setup.
- Pre-fight pinned card.
- One local SQLite authority shared by the native overlay and localhost map, with full run snapshots, bounded revisions, settings, and one-time legacy JSON migration.

### Phase 2 — contextual assistance

- Click-open guide-grounded chat.
- User-triggered screenshot classification plus default-off 30-second Visual Memory.
- Suggested current checkpoint with explicit confirmation.
- Party-aware readiness checks.

### Phase 3 — richer coaching

- Reviewed level-by-level build plans.
- Map/landmark navigation aids.
- Optional event-triggered warnings after reliability testing.
- Acts 2 and 3 using the same content schema.

## Explicit non-goals for Act 1 MVP

- Vanilla mode performs no memory reading, mod injection, combat automation, general gameplay input control, or save manipulation. An optional separately installed read-only telemetry integration may publish structured local events, but the companion must remain complete without it, label the game as modded, and never mutate game state or silently complete route progress. Only an explicit external Computer Use session may click/type, and only inside the open BG3 custom-marker flow.
- No default or high-frequency screenshot stream. Visual Memory is an explicit, default-off 30-second sample to the configured provider.
- No claim that every quest, item, or inspiration is covered.
- No automatic progress changes from uncertain screen recognition.
- No free-form LLM route generation.

## Optional telemetry boundary

The companion has one product and one persisted run model, not a separate mod edition:

```text
Clean run:  BG3 -> local capture + player confirmation -> shared overlay
Modded run: BG3 -> read-only event bridge -> local JSON -> shared overlay
                         absent / stale / invalid -> Vanilla fallback
```

- Vanilla is the default, complete path.
- Live Events is explicitly enabled and labeled as modded.
- The backend treats the snapshot as bounded, untrusted advisory input.
- Events may alter transient wording only; they never mutate party, equipment, route, or completion state.
- The bridge subscribes to documented events and writes one local snapshot. It makes no Osiris mutation calls, performs no game input, and reads no saves.

## First implementation slice

The smallest implementation that proves the product is:

1. Remove legacy turn recording from the primary flow.
2. Rename the product surface and detect BG3.
3. Add a draggable pet placeholder and click-open peek card.
4. Ship five curated checkpoints: Nautiloid, Grove entrance, Harpy beach, Whispering Depths, and Owlbear Cave.
5. Persist level plus completed checklist items locally.
6. Validate the overlay during real BG3 play before importing all Act 1 content.

This slice tests the essential question: does the pet deliver the right warning early enough to change an Honor Mode decision without getting in the way?
