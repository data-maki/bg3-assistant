# Honor Mode Workbook Contract

The workbook is the reviewed content layer for party planning. It is intentionally separate from route progress and combat detection so build advice can improve without changing fight facts.

## What the player should be able to answer

1. Which four builds fit the run I want?
2. What changes at my current level?
3. Who should own each contested item, and when can I safely claim it?
4. Is a location an exact map pin, an area anchor, or still unknown?

## Review states

- `Reviewed – app-ready`: complete level plan already used by the assistant.
- `Reviewed – Act 1`: levels 1–7 and Act 1 equipment reviewed; safe for Act 1 selection.
- `Source template – review required`: useful research, but never shown in the app build picker.

Source-only rows remain visible so ideas are not lost, but they cannot silently become recommendations.

## Act 1 permanent-power ledger

The walkthrough tracks high-value world rewards separately from ordinary loot so they cannot disappear inside a generic area checkbox:

| Step | Unlock | Completion proof |
|---|---|---|
| Apothecary's Cellar | Bracers, Basilisk Oil, unique quasit scroll, tome | Lab opened and all four assets checked |
| Shovel | Permanent Cheeky Quasit familiar | Resummon spell visible on the intended long-term owner |
| Necromancy of Thay | Speak with Dead, Forbidden Knowledge, Act 3 continuation | Reader and page outcomes recorded; tome retained |
| Mourning Frost | Cold quarterstaff | Helve, Crystal, and Metal combined |
| Masterwork weapon | One Sussur Silence weapon | Build-fit base weapon forged and assigned |
| Blood of Lathander | Legendary mace for Act 2 | Crest inserted; mace assigned |

These are manual route steps, not build assumptions. Selecting a build never marks a world reward acquired, and screenshot analysis never completes one.

## Recommended default

The safest general Act 1 composition is:

| Party job | Build | Why it is here |
|---|---|---|
| Face + ranged control | 10/1/1 Control Martial | Dialogue, ranged burst, skills, later deterministic control |
| Scout + locks + initiative | Gloomstalker Assassin | Acts early and removes a priority target before it acts |
| Support + area control | Stars of the Circle Light Cleric | Recovery, Radiating Orb, Spirit Guardians, encounter stabilization |
| Frontline control | Open Hand Monk | Mobile single-target control and burst from level 4 |

This is a default, not a universal tier list. `Party Presets` includes alternatives for alpha strike, no-elixir safety, ranged control, wet/cold control, simplicity, and fire/control.

## Sheet responsibilities

### Party Planner

- One party-wide act and level selector.
- One character and one reviewed build per slot.
- Shows only `DO THIS LEVEL` and `PLAY THIS LEVEL`.
- Calculates role coverage and whether every selected build is online.
- Keeps equipment out of the level-up decision.

### Party Presets

- Four-build packages organized by run objective.
- Explicit complexity, rest pressure, gear contention, and biggest avoid.
- Research-only parties are visibly blocked from the picker.

### Build Catalog

- Stable build ID, split, roles, online level, Act 1 breakpoint, priority gear, Honor friction, review state, and source.
- The picker reads only reviewed rows.

### Level Actions

- One row per `build + character level`.
- No future-level teaser in the default experience.
- Separates the level-up choice from how to play the build now.

### Equipment Priority

- One deduplicated row per `act + item`.
- Tracks claim status, recommended owner, eligible builds, timing, acquisition gate, and source class.
- Map precision is explicit:
  - `Exact reviewed pin`: safe to export.
  - `Area anchor — review before exact pin`: useful for navigation, not automatic marker placement.
  - `Unknown — do not pin`: must remain blocked.

## Source authority

- Fight order, preparation, minimum levels, and route notes: [project spreadsheet](https://docs.google.com/spreadsheets/d/1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0).
- Party archetypes: [community party reference](https://docs.google.com/spreadsheets/d/1HhiUZcQ1gXjvsaJSpvccG_0Jm0fn7lgYaOYdQxuWSQs/edit?gid=1486234924#gid=1486234924).
- Early-game build progression: [Morgana Evelyn Honor Mode party guide](https://drive.google.com/file/d/1iqPT3rGJ6-YFtMNot5GGkIVCYUS_hMjf/view).
- Coordinated Hold / critical-smite research party: [PXP 004 Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3294601861).
- Item acquisition links: BG3 Wiki pages recorded per equipment row.

Every app-visible statement must retain one of three labels: guide fact, reviewed assistant suggestion, or unknown.

## Tool integration order

1. Import `Build Catalog`, `Level Actions`, and `Equipment Priority` into the existing normalized data loaders.
2. Add the five Act 1-reviewed builds to the native build picker; keep the four Steam concepts blocked.
3. Use the same role tags for native party-coverage warnings.
4. Resolve equipment ownership per party member and show one conflict warning when two selected builds want the same unique item.
5. Export only `Exact reviewed pin` rows to BG3 marker placement. Keep area anchors visible on the localhost planning map.
6. Expand Act 2 and Act 3 through the same schema only after their level rows, equipment ownership, and map coordinates pass review.

## Next research queue

- Review the four Steam-template builds level by level before exposing them.
- Replace all Act 1 area anchors with exact pins where the item has one deterministic acquisition point.
- Add explicit alternative-owner rules for mutually exclusive quest rewards.
- Add Act 2 only after the Act 1 picker, current-level action, equipment ownership, and exact-pin loop are shipped from this same dataset.
