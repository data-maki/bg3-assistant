# Mod.io listing draft

> **Blocked:** this copy is prepared for a future Toolkit-only edition. Do not attach the current Script Extender `.pak` or set this listing live.

## Basics

- **Name:** BG3 Honor Companion Bridge
- **Summary:** Optional read-only local context for the BG3 Honor Mode Assistant. Progress always stays player-confirmed.
- **Mature content:** No
- **Suggested tags:** User Interface, Quality of Life
- **Platforms:** Select only platforms proved with the Toolkit build. Do not request Mac or console curation before live platform testing.

## Description

BG3 Honor Companion Bridge adds a small, read-only integration channel for the separate BG3 Honor Mode Assistant.

It can expose recent combat, downed-character, roll, level, equipment, rest, and session context. The companion uses that context only for transient warnings. It never controls the game and never marks a walkthrough step complete—the player remains responsible for Done, Skip, and Revisit.

The desktop companion remains fully functional without this mod. If the integration is absent, stale, or incompatible, it falls back to Vanilla guidance.

### Safety boundary

- No combat or input automation
- No memory reading
- No save manipulation
- No automatic route completion
- No cloud screenshot stream
- Bounded, local-only context

Enabling any BG3 mod disables achievements. Use a separate modded profile and back up saves before testing.

## First file

- **Version:** 0.1.0
- **Changelog:** Initial read-only integration candidate for the BG3 Honor Mode Assistant.
- **Dependency:** None may be declared until the Toolkit-only transport is implemented. The third-party Script Extender package is not an eligible substitute.

## Media

- Logo: `thumbnail.png` (1280×720 PNG, original project artwork)
- Gallery: add screenshots only from a disposable modded profile after the Toolkit runtime is proved
