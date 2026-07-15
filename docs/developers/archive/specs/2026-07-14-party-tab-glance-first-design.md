# Party Tab: Glance-First Roster — Design

**Date:** 2026-07-14
**Status:** Approved
**Surfaces:** Mac app (`mac/BG3Assistant/PartyTabView.swift`) and web map panel (`backend/app/static/map/js/panels.js` + `styles.css`)

## Problem

The Party tab gives every element equal visual weight, so the user reads
everything to find the one thing that matters. Each member card stacks three
pickers (level, build, status) above a multi-line "DO NOW" text block, and the
page surrounds that with a party-level selector, camp disclosure, Karlach
outcome toggles, an include-camp toggle, and an advanced-overrides section.

The tab serves two jobs with very different frequencies:

- **Setup** (who is active, which build, what status) — done once, rarely revisited.
- **The insight** ("what do I take at this level-up?") — the reason the user
  returns to the tab, currently buried as body text under the controls.

## Goal

Surface the per-member "do now" action as the default view; move editing and
configuration behind one interaction. Same functionality, inverted hierarchy.

## Design

### 1. Glance row (new default state per member)

One compact line per roster member:

```
[status dot] Astarion  L4 · Thief-Assassin   Take Thief · Second-Story Work   ›
```

- Contents: status dot (colored by roster status, reusing existing theme
  colors), bold name, `L{level}`, the assigned build's `name`, then the
  current level's action (`take` + subclass/first choice fragment), truncated
  to a single line.
- **Emphasis rule (derived, no new state):** if the assigned build has a step
  at exactly the member's current level, the action renders in the gold accent
  (fresh level-up guidance). Otherwise the row is dim and quietly shows the
  most recent applicable step.
- Members with no assigned build show "Pick a build →" as the action line.
- A chevron indicates the row expands.

### 2. Expand to edit (accordion)

Clicking a row expands it in place into the equivalent of today's card:

- Level picker (L1–12), build picker, status picker, custom-name text field
  (custom characters only).
- Full "DO NOW" detail: take, subclass choice, choices text, tactics line.
- Exactly one row may be expanded at a time; expanding another collapses the
  first. Expansion state is ephemeral UI state — never persisted to the run
  store and never synced between surfaces.
- The existing dead/departed confirmation alert continues to fire from the
  status picker unchanged.

### 3. Page chrome

- Header keeps "Active party N/4".
- "Camp & unavailable · N" stays a disclosure; members inside use the same
  glance rows.
- A single **"Party setup"** disclosure at the bottom collects: the party-level
  quick-set (L1–7), the include-camp-builds toggle, the advanced
  class/capability overrides, and the map-detection status line.
- **Exception:** the Karlach outcome toggles stay a visible orange banner when
  triggered (Karlach dead). It is a rare, consequential one-time decision and
  adds no steady-state reading.

### 4. Implementation shape

- **Mac:** rework `RosterMemberEditor` into a `GlanceRow` (collapsed) plus the
  existing editor body (expanded), driven by a single `@State` expanded-member
  ID in `PartyTabView`. No model, store, or backend changes.
- **Web:** same treatment inside `renderParty()` — collapsed article rows with
  a click-to-expand body, driven by an ephemeral `expandedRosterId` in client
  state. New CSS for the glance rows in `styles.css`.
- Both surfaces keep identical structure and terminology so the tab reads the
  same in the app and on the map.

## Error handling

Unchanged. Status-change confirmations (dead/departed) still gate through the
existing alert/confirm flow. Missing builds degrade to the "Pick a build →"
row, mirroring today's "Pick a build to see this level's choices" fallback.

## Testing & verification

Backend tests cover roster state APIs only, not client-side rendering, so no
test changes are expected. Verification is visual on both surfaces:

1. Mac app: build and open the Party tab; confirm glance rows, accordion
   expand, setup disclosure, Karlach banner behavior.
2. Web map: serve the map, confirm the same states in the Party panel.
3. Shipping the web change requires rebuilding the bundled PyInstaller backend
   (the Mac app supervises the frozen backend on port 8787).

## Out of scope

- Tracking applied/acknowledged level-ups as persisted state (emphasis is
  derived from build data instead).
- Any change to builds data, run-state models, or backend endpoints.
- The Loadout/Gear tabs and overlay views.
