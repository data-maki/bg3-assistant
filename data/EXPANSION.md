# Expanding item coverage to Act 2 and Act 3

Act 1 item markers are enriched end to end: each item carries what it does
(`effect`), exactly where it comes from (`acquire`), and a `wiki` source link,
joined from `data/item_effects.json` into both the web map payload and the
Mac app's build loadouts. This file records how to repeat that for Acts 2–3.

## Data pipeline (what worked for Act 1)

1. **Curate the items per build** in `data/build_gear.tsv` (`Act` column = 2 or 3).
   Only items mapped to a `Build IDs` entry show up — the map is a build
   shopping list, not an item database.
2. **Fetch effects + acquisition** (idempotent; hand edits survive re-runs):
   ```sh
   cd backend && python3 scripts/fetch_item_effects.py --act 2
   ```
   - `effect` comes from the bg3.wiki lead paragraph (MediaWiki `prop=extracts`).
   - `acquire` comes from the `where to find =` parameter of the page's
     equipment template (`action=parse&prop=wikitext`) — the rendered section
     headings are icon templates and come back empty via extracts, so the
     wikitext parameter is the reliable source.
3. **Fetch icons** with the same MediaWiki API
   (`prop=pageimages&pithumbsize=96`, then download the thumbnail into
   `backend/app/static/map/icons/<item-key>.webp` and add the entry to
   `data/item_icons.json`). Worth folding into `fetch_item_effects.py` when
   Act 2 lands.
4. **Timed/missable events**: extend `data/act1_timed_events.json`'s pattern
   with per-act files sourced from
   https://bg3.wiki/wiki/Time-sensitive_activities (Act 2 and 3 sections).

## Map plumbing for the new acts

MapGenie hosts one map per act region; ids discovered from
`https://mapgenie.io/api/v1/maps/123/data` (`maps` array):

| Map | id | slug | tiles |
|---|---|---|---|
| Nautiloid | 122 | `nautiloid` | `baldurs-gate-3/nautiloid/...` |
| Wilderness (Act 1) | 123 | `wilderness` | `baldurs-gate-3/wilderness/default-v4/{z}/{x}/{y}.jpg` |
| Shadow-Cursed Lands (Act 2) | 124 | `shadow-cursed-lands` | check `window.mapData.mapConfig.tile_sets` on the map page |
| Baldur's Gate (Act 3) | 125 | `baldurs-gate` | same |

Per new act you need (all steps have Act 1 precedents in the code):

- **Tile config**: fetch the map page, read `window.mapData.mapConfig`
  (`tile_sets[0].pattern`, `bounds`, zooms) → a `MAP_TILES`-style config and a
  mosaic block for `backend/app/mercator.py` (`TILE_ORIGIN`/`MOSAIC_TILES`
  come from `tile_sets[0].bounds` at the chosen zoom).
- **Marker coordinates**: `https://mapgenie.io/api/v1/maps/<id>/data` lists
  every named location with lat/lng — name-match fights/items exactly like
  `MG_FIGHT_COORDS` / `MG_ITEM_COORDS` in `backend/app/map_data.py`.
- **In-game overlay alignment**: `backend/app/map_align.py` needs one mosaic
  per act (cache dir per map id) and a map-id hint from the align context —
  the ORB registration itself is act-agnostic.

## Curation sources

- Community cheat sheet (per-act item lists):
  https://www.reddit.com/r/BaldursGate3/comments/16acy9l/bg3_cheat_sheet_for_items_in_each_act_spoilers/
  (Reddit blocks scripted fetches; open in a browser. Equivalent maintained lists below.)
- Gamestegy checklists: https://gamestegy.com/post/bg3/1068/act-1-unique-and-missable-items
  and https://gamestegy.com/post/bg3/1077/act-3-unique-items
- Item index PDFs: https://www.scribd.com/document/742804259/BG3-Item-Index-Cheat-Sheet
- Authoritative per-item pages: https://bg3.wiki (effects, prices, "where to find")
- Build sources already used per build: see `Primary source` in `data/build_overview.tsv`
