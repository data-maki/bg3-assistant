# Architecture

## Product boundary

The product is a native macOS in-game overlay. It presents one current danger, the outcome to avoid, the recommended action, manual run progress, a focused character sheet, and guide-grounded chat. The local browser map is the only intentional external surface.

There are no BG3 mods, memory readers, save editors, automated inputs, periodic screenshots, or background recordings. Configured AI chat may attach one player-visible BG3-window screenshot to the next message.

## Runtime

```text
Bundled guide data
       |
Native SwiftUI overlay <-> SQLite run + loadout state
       |                       |
       +---- localhost API ----+
                    |
    Browser map + optional OpenRouter chat/import
```

- `mac/BG3Assistant`: menu-bar lifecycle, in-game overlay, party/loadout UI, chat, and native persistence.
- `backend/app`: guide parsing, readiness/chat grounding, reusable public-URL build import, localhost state bridge, and browser-map server.
- `data`: reviewed route, walkthrough, build, equipment, and marker inputs.
- `backend/app/static/map`: browser map and walkthrough implementation.

Build progression is shared across the full level range. Equipment, coordinates, and map metadata are act-scoped so advancing cannot leak an earlier act's objects into the current loadout:

```text
TSV exports (seed-only)          state.sqlite3 catalog (authoritative)
  data/gear/act{1,2,3}.tsv  --->   items         (item facts + wiki enrichment)
  data/build_overview.tsv   --->   builds        (origin: seed | import)
  data/build_levels.tsv     --->   build_levels
                                   build_items   (per-build opinions per item)

Run state: Act 1 --review and lock--> Act 2 --review and lock--> Act 3
```

Builds and items live in relational tables inside the shared SQLite database (`backend/app/catalog.py`). The checked-in TSV/JSON exports seed the catalog exactly once per guide version (`catalog_seed_version` setting); after that the database is authoritative and the Google Sheet's per-build tabs (everything after "Inspiration on the go") are no longer a data source. Build rows retain validated creation/respec recipes and typed ability sources alongside target notes. A URL import inserts one `builds` row plus `build_items` joins, derives and validates a legal BG3 creation recipe, and upserts unknown items with a best-effort bg3.wiki effect lookup. Reviewed catalog facts always win over an import's sparse copy. `GET /api/items` serves the catalog to the native slot picker.

Every act has a `data/acts/act{1,2,3}.json` contract. `GET /api/acts/{act}/guide` returns the requested act and route-availability flag, act-scoped checkpoints, walkthrough, and timed events, the shared build catalog, and metadata for all acts; an unavailable route returns empty act-scoped guide data rather than another act's guidance. Acts 1 and 3 have reviewed routes. Act 1 also has the local browser map; Act 3 uses a public Baldur's Gate map handoff because its route records are area-level rather than local-map coordinates. Act 2 currently has sourced equipment coordinates and a public Shadow-Cursed Lands map handoff. Its route is intentionally marked unavailable, which keeps the Act 2 to Act 3 gate locked.

The native app starts and owns the packaged backend; the browser map is a client of that local service and has no independent persistence authority. The browser map and native overlay share run state and validated imported builds through the same SQLite database. Browser member updates merge by ID so partial or older clients cannot erase fields they do not understand; native polls the shared snapshot and rejects a stale write if the map changed it first. When the installed guide version changes, the native app archives the active run and creates a clean run against the new guide while retaining valid character and build presets.

A build import never changes party membership; assigning the imported build remains an explicit player action for the initiating member. Import fetching rejects non-public destinations and sends only extracted public-page text to the configured OpenRouter structured-output model (Gemini 3 Flash by default).

Gear contention resolves deterministically on the native side: each item goes to the member whose build was assigned earliest (`HonorRun.buildAssignedAt`, "first to request"), ties alphabetical by build name, and a player's manual "Give to X" override (`gearAssignmentOverrides`) always wins. Players can also swap any Loadout slot to another valid catalog item for the current act (`plannedSlotOverrides`); swapped picks join assignment, route pickups, and maps exactly like build picks, while `equippedByMember` stays the separate player-confirmed pickup ledger.

## State authority

- Guide data is reviewed source material.
- Route recommendations are deterministic suggestions.
- Progress, outcomes, party status, and equipment ownership are player-confirmed state.
- AI prose cannot complete activities or replace guide facts.

## UI ownership

- `Now`: current danger, outcome to avoid, recommended action, and progress controls.
- `Run`: route order, focus changes, resolved archive, and decision outcomes.
- `Party`: compact current-level guidance, whole-roster Active/Camp/Unrecruited placement and active-four selection, levels, builds and URL import, inline creation/respec ability recipes, expandable progression/source detail, and Withers hirelings.
- `Loadout`: active-character carousel, current-act equipment, ownership, conflicts, and slot alternatives.
- `Act`: irreversible equipment/consequence review gate and current-act map metadata.
- `Chat`: contextual overlay action with speech input; it is not a primary navigation tab.
- `Map`: explicit action that opens the local browser map.
