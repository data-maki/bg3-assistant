# Gear database, deterministic assignment, and slot swapping

Decisions made with the user on 2026-07-17.

## Goals

1. **Relational build/item store.** Builds, their level plans, and their gear picks
   move from TSV-parsed-at-boot + JSON blobs into proper SQLite tables
   (analytics-ready). Uploading a build adds rows, not blobs.
2. **Spreadsheet decoupling.** Only tabs up to and including "Inspiration on the
   go" in the source Google Sheet remain authoritative (fights, notes, tips,
   Great builds overview, tadpole locations). The eight per-build detail tabs
   (Bard Archer → Bladesinger, incl. Open Hand Monk) are being removed from the
   sheet; the checked-in TSV exports migrate into the DB **once**, after which
   builds live only in SQLite and arrive via the import pipeline.
3. **Deterministic gear assignment.** Every contested item resolves to exactly
   one character: manual player override wins; otherwise the member whose build
   was assigned earliest ("first to request", tracked by assignment timestamp);
   ties break alphabetically by build name, then member name. Build-priority
   ranks stop being the resolver and become advisory context.
4. **Slot swapping with informed trade-offs.** Clicking a slot in the Loadout
   paper doll lets the player replace the build's pick with any valid catalog
   item for that slot and act. Every option explains its effect on hover.

## Data layer (backend, existing `state.sqlite3` via `RunDatabase`)

New tables, created in `RunDatabase.connect()`:

- `items(item_key PK, name, slot, act, region, acquisition, game_x, game_y,
  map_objective, effect, acquire, wiki, icon, updated_at)` — item **facts**,
  shared across builds. Enrichment columns (`effect`, `acquire`, `wiki`,
  `icon`) come from `item_effects.json` / `item_icons.json` at seed time and
  from a best-effort bg3.wiki fetch when an import introduces an unknown item.
- `builds(build_id PK, name, honor_status, role, final_split,
  class_progression, starting_abilities, starting_scores_json,
  target_scores_json, play_pattern, caveat, source_url, origin
  ('seed'|'import'), created_at)`
- `build_levels(id PK, build_id FK, level, take, subclass_choice,
  feats_spells, what_changes, confidence)`
- `build_items(id PK, build_id FK, item_key FK, act, priority, minimum_level,
  maximum_level, requirement, alternative, why)` — per-build **opinions**
  about an item (priority, level window, alternatives).

Migrations (idempotent, guarded by a `settings` key `catalog_seed_version` =
`GUIDE_VERSION`):

1. Seed `items` + `builds` + `build_levels` + `build_items` from the checked-in
   TSVs (`origin='seed'`).
2. Convert every `custom_loadouts` JSON row into relational rows
   (`origin='import'`), upserting unknown items, then drop `custom_loadouts`.

Serving changes:

- `load_builds()` / `load_gear()` read from the DB (join `build_items` ×
  `items`); the `/api/route` payload shape is unchanged so existing app
  surfaces keep working. TSV parsing survives only inside the seed step.
- New endpoint `GET /api/items` (optional `act`, `slot` filters) → the catalog
  the slot picker browses.
- `POST /api/builds/import` inserts relational rows and best-effort-enriches
  unknown items; response shape (`ImportedBuild`) unchanged.

## App layer (SwiftUI)

`RunState` additions (all optional so old snapshots decode):

- `buildAssignedAt: [String: Date]?` — memberID → when their current build was
  assigned; stamped centrally wherever `buildId` changes (`updatePartyMember`,
  import flows), cleared when the build is removed.
- `gearAssignmentOverrides: [String: String]?` — itemKey → memberID, the
  player's manual "give it to X" decision.
- `plannedSlotOverrides: [String: [String: String]]?` — memberID → slot id →
  itemKey chosen from the catalog in place of the build's pick.

Resolver (`GearLogic.assignments`, pure and unit-tested): input is the active
members (with build names + assignment dates), each member's wanted item keys
(build picks plus slot overrides, filtered by act/level), and the override
map; output is `[itemKey: memberID]`. Manual override wins when the override
target is still active and still wants the item; otherwise earliest
`buildAssignedAt`; ties alphabetical by build name, then member name.

UI:

- `gearOwner` / `gearConflict` are re-based on the resolver: "Assigned to
  Karlach (build assigned first)" with a one-click "Give to Shadowheart
  instead" that writes `gearAssignmentOverrides`. `equippedByMember` remains
  the separate *confirmation* layer ("the player actually picked it up").
- Slot cell click (pinned drawer) gains a "Change pick" section listing valid
  catalog items for that slot + act, each with its effect text inline and on
  hover; choosing one writes `plannedSlotOverrides`; a "build pick" action
  reverts. Swapped-in items participate in assignment, pickups, and maps like
  build picks.
- Downstream consumers (route pickups, act gear review, Now-page target) keep
  their semantics but read the resolver's planned owner instead of
  priority-rank inference.

## Testing

- Backend pytest: seed idempotency, `custom_loadouts` migration, `/api/items`
  filters, import writing relational rows + unknown-item upsert.
- Swift: resolver unit tests (recency, alphabetical tie, override, stale
  override, level/act filtering) using the repo test target; locally verified
  via the standalone swiftc assertion runner (no XCTest in CLT toolchain).
- Runtime: rebuild the bundled backend + app (`mac/scripts/build-app.sh`) —
  the app supervises a frozen PyInstaller backend, so backend changes ship
  only via bundle rebuild — and exercise the Loadout tab.
