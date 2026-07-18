# Overlay UI redesign: Now (A2), Route (B3), Loadout (C2), gear targets

Approved 2026-07-17. Covers the mac overlay's Now view, Route tab, Loadout tab,
a shared design-system foundation, and two new features: equipment-as-target
and route-integrated gear pickups.

## Foundation (applies everywhere)

- **Type scale, five steps, nothing smaller:** overline 9pt heavy serif caps
  (section headers only), caption 10pt, body 12pt, row title 13pt semibold,
  page title 17pt bold serif. Kills the current 7.5–28pt sprawl.
- **Color roles, theme-only:** gold = identity/section headers; success =
  done/ready; caution = underleveled; warning = attention/skipped; danger =
  run-enders. No raw `.orange`/`.red`/`.green`. Encounter tints (fight
  red-orange, talk blue) move into `BG3Theme`.
- **Icon gutter replaces caps-label soup:** `→` do, `✕` avoid, `◆` why,
  `★` reward, `◈` gear. One prominent button per surface; navigation and
  rare actions go to overflow.
- **Jargon pass:** "RESOLVED"→"done", "No reviewed pick"→plain language,
  "requirement(s)" pluralization fixed, spreadsheet row/sheet references
  dropped from primary UI.
- **Quick wins:** delete dead `levelPlanCard`; resurrect the dead "Later"
  gear section (C2); AsyncImage gets a visible fallback; off-theme
  `.roundedBorder`/`.bordered` controls replaced with themed equivalents.
- **Naming:** `PlannerTab.route` rawValue "Run" → "Route". *Run* remains the
  saved-playthrough concept (`RunStore`, `HonorRun`).

## Gear target feature

- `HonorRun.gearTarget: GearTarget?` where `GearTarget = {memberId, buildId,
  gearId}`. Optional field → old snapshots decode unchanged. One active
  target; retargeting swaps; queue is out of scope.
- Setting a target replaces the Now goal card and peek-card headline.
  Route recommendation logic underneath is untouched.
- **Path derivation** (no structured gear→step data exists; derived):
  1. Level gate row if member level < `minimumLevel`.
  2. Split `gear.region` on "/", case-insensitive containment match against
     `WalkthroughStep.area`/`.region`; unresolved matches in route order
     become checkable rows (checking = normal step disposition).
  3. Free-text `requirement` as a non-checkable info row.
  4. Acquisition text always last, with map button.
  5. No matches → level gate + acquisition + map only. Never fake steps.
- Path list collapsible; 4 rows expanded, "· N more" beyond.
- Primary action "Got it" = equip via existing `toggleGear` + clear target.
  Equipping from Loadout also auto-clears a matching target. "Clear target"
  restores the route goal. Only current-act gear is targetable; invalid
  member/build clears the target silently; conflict notes carry over.

## Now view (A2 — briefing layout)

Three fixed zones inside the Now tab: scrolling body (title, type/danger
chips, icon-gutter fact rows, disclosure for escape plan/checks/source) and a
**pinned action bar** that never moves. Decision trade-offs render in the body
above the commit buttons. One shared goal-card component with three modes:
walkthrough step, checkpoint (fight), gear target — replacing
`walkthroughNowCard`, `encounterHUD`, and their duplicates. Decision steps
rename footer buttons to outcome verbs (primary = recommended outcome,
"Went differently" menu = alternatives, Skip).

## Route tab (B3 — flat checklist + pushed detail)

- Flat list, sticky phase headers, one click target per row, `›` pushes a
  full-panel `StepDetailView` with Back (lightweight enum page state, slide
  transition; no NavigationStack).
- The current objective card is removed — Now owns it; the list marks the row
  "now".
- Progress header: bar + "24/58 done" + Act 2 gate line (expandable blockers).
- Done/Skipped collapse into bottom summary rows.
- **Pickups:** per phase, one collapsed "◈ Pickups here · N" row expanding to
  unowned current-act gear for active members' builds whose region matches
  that phase's step areas (same match rule as path derivation). Unmatched
  gear → "Other pickups" bottom group. Pickup `›` pushes shared
  `GearDetailView` (includes Set as target).

## Loadout tab (C2 — paper doll + drawer)

- Party strip on top (replaces blind chevron carousel); un-geared members
  flagged; one-line member summary with "edit ›" deferring to Party tab
  (embedded `RosterMemberEditor` removed from this tab).
- Uniform fixed-height slot cells in a 2-column doll layout; ranged/extras as
  full-width rows; "Later" locked row; confirmed count in header.
- **Drawer:** hover previews an item (effect, acquisition, conflict) with zero
  clicks; click pins (selection ring, drawer persists); actions (Set as
  target / Mark equipped / Map / Give to X) only when pinned. Idle drawer
  shows a one-line summary. `◈` marks the targeted item's cell.
- Drawer content = the same `GearDetailView` the Route tab pushes.

## Out of scope

Multi-target queue, RunStore revision-restore UI, backend/data-format
changes.
