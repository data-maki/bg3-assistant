# Overlay UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved redesign (spec: `docs/superpowers/specs/2026-07-17-overlay-ui-redesign-design.md`): A2 Now view, B3 Route tab, C2 Loadout tab, shared foundation tokens, gear-as-target, and route pickups.

**Architecture:** Pure derivation logic (`GearLogic`) is separated from `AppState` so it is unit-testable; all gear presentation flows through one shared `GearDetailView`; the Now goal card becomes one component with three modes; Route gains lightweight enum-based page push (no NavigationStack).

**Tech Stack:** SwiftPM (swift-tools 6.0, macOS 14+), SwiftUI, XCTest (new test target).

**Deviation — no commits:** the working tree contains the user's uncommitted work on the same files (dirty `main`). Every "commit" step is replaced by "verify build". The user commits when they choose.

---

### Task 1: Foundation tokens + shared components

**Files:** Modify `mac/BG3Assistant/AssistantGlassStyle.swift`

- [ ] Add to `BG3Theme`: `fightTint = Color(red: 0.92, green: 0.42, blue: 0.34)`, `talkTint = Color(red: 0.55, green: 0.78, blue: 0.95)` (moved from RouteTabView hardcodes).
- [ ] Add `enum BG3Type` with the five-step scale:
```swift
enum BG3Type {
    static let overline = Font.system(size: 9, weight: .heavy, design: .serif)
    static let caption = Font.system(size: 10)
    static let body = Font.system(size: 12)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let pageTitle = Font.system(size: 17, weight: .bold, design: .serif)
}
```
- [ ] Add shared `FactRow` (icon gutter row: fixed 16pt glyph column + body text) and `StatusChip` (10pt semibold text in tinted capsule, ≥16pt tall).
- [ ] Verify: `cd mac && swift build 2>&1 | tail -3` → `Build complete!`

### Task 2: Model changes

**Files:** Modify `mac/BG3Assistant/BG3Models.swift`

- [ ] `PlannerTab.route` rawValue `"Run"` → `"Route"` (line 671).
- [ ] Add below `BuildGear`:
```swift
struct GearTarget: Codable, Hashable {
    let memberId: String
    let buildId: String
    let gearId: String
}
```
- [ ] `HonorRun`: add `var gearTarget: GearTarget?` after `focusedWalkthroughStepId`.
- [ ] Verify build.

### Task 3: GearLogic + test target (TDD)

**Files:** Create `mac/BG3Assistant/GearLogic.swift`, `mac/Tests/BG3AssistantTests/GearLogicTests.swift`; Modify `mac/Package.swift`

- [ ] Add test target to `Package.swift`:
```swift
.testTarget(name: "BG3AssistantTests", dependencies: ["BG3HonorAssistant"], path: "Tests/BG3AssistantTests")
```
- [ ] Write failing tests covering: `regionParts` splits "A / B" and trims; `matchingSteps` matches by area/region containment (case-insensitive, both directions), returns route order, empty parts → empty; `pathRows` order = levelGate → steps(done flags from dispositions) → info(requirement) → acquisition, level gate only when member below minimum, fallback = acquisition only; `pickupsByPhase` buckets by first matched step's `phaseOrder`, unmatched → `other`.
- [ ] Run `swift test` → FAIL (GearLogic undefined).
- [ ] Implement `GearLogic`:
```swift
enum GearLogic {
    enum PathRow: Equatable {
        case levelGate(required: Int, partyLevel: Int)
        case step(WalkthroughStep, done: Bool)
        case info(String)
        case acquisition(String)
    }
    struct Pickup: Equatable {
        let gear: BuildGear
        let memberId: String
        let memberName: String
    }
    static func regionParts(_ region: String) -> [String]
    static func matchingSteps(for gear: BuildGear, in walkthrough: [WalkthroughStep]) -> [WalkthroughStep]
    static func pathRows(gear: BuildGear, memberLevel: Int, walkthrough: [WalkthroughStep],
                         dispositions: [String: CheckpointDisposition]) -> [PathRow]
    static func acquireText(_ gear: BuildGear) -> String        // acquire ?? acquisition
    static func pickupsByPhase(_ pickups: [Pickup], walkthrough: [WalkthroughStep])
        -> (byPhase: [Int: [Pickup]], other: [Pickup])
    static func priorityRank(_ priority: String) -> Int          // moved from LoadoutTabView
}
```
Matching rule: for each lowercased region part and step, match when `step.area/region` contains the part or the part contains the non-empty area. Steps sorted by `order`. `pathRows` includes completed matches with `done: true` (progress display).
- [ ] `swift test` → PASS.

### Task 4: AppState gear-target + pickups state

**Files:** Create `mac/BG3Assistant/AppState+GearTarget.swift`; Modify `mac/BG3Assistant/AppState+Party.swift` (`toggleGear`), `mac/BG3Assistant/AppState.swift` (activity accessors, `completeCurrentActivity` guard)

- [ ] `AppState+GearTarget`:
```swift
extension AppState {
    var gearTargetContext: (member: PartyMember, gear: BuildGear)? // nil unless member+build+gear all resolve and gear.act == selectedAct
    var gearTargetPath: [GearLogic.PathRow]                        // pathRows(...) for the context
    var routePickups: [GearLogic.Pickup]                           // unowned, current-act, available-at-level gear across activeParty builds, deduped by itemKey+member
    func setGearTarget(_ gear: BuildGear, for member: PartyMember) // guard current act + buildId; persistRun()
    func clearGearTarget()
    func completeGearTarget()                                      // equip via toggleGear if needed, clear, persist
}
```
- [ ] `toggleGear`: after a successful toggle that *equips* the targeted item for the target member, clear `run.gearTarget` before the single `persistRun()`.
- [ ] Peek/Now integration in `AppState.swift`: when `gearTargetContext` is non-nil, `currentActivityTitle` = "Get \(gear.item)", `currentActivityArea` = gear.region, `currentActivityLabel` = "TARGET"; `completeCurrentActivity()` routes to `completeGearTarget()`. Invalid stored targets simply render as no-target (visual fallback); `updatePartyMember` clears a target whose member/build no longer resolves.
- [ ] Verify build + `swift test`.

### Task 5: Shared GearDetailView + conflict extraction

**Files:** Create `mac/BG3Assistant/GearDetailView.swift`; Modify `mac/BG3Assistant/AppState+Party.swift` (add `gearConflict(for:member:)` + `GearConflict` moved from LoadoutTabView)

- [ ] Move `GearConflict` + conflict computation from `LoadoutTabView` into `AppState+Party` (`func gearConflict(for gear: BuildGear, member: PartyMember) -> GearConflict?`), using `gear.itemKey` for rival matching and `GearLogic.priorityRank`.
- [ ] `GearDetailView(gear:member:showsActions:)` renders: item icon + name + slot, `★` effect (visible, not tooltip), `→` acquisition, `◆` requirement, `⚠` conflict line, and when `showsActions`: Set as target (`◎`, disabled for non-current-act with reason), Mark equipped / Transfer, Map, Give to N. All state/actions via `@EnvironmentObject appState`.
- [ ] AsyncImage fallback: phase-based `AsyncImage` showing the shield glyph on `.failure` and while empty.
- [ ] Verify build.

### Task 6: Now tab (A2) + OverlayView shell

**Files:** Create `mac/BG3Assistant/NowTabView.swift`; Modify `mac/BG3Assistant/OverlayView.swift`

- [ ] `NowTabView` = `VStack { ScrollView(body); Divider; footer }` with mode precedence: gear target → walkthrough step → checkpoint → act>1 / complete / offline states. Body: `pageTitle` title, `StatusChip`s (kind + danger — danger now explicit, not a 9%-opacity tint), `FactRow`s (`→` do, `✕` avoid, `◆` why, `★` rewards), decision trade-offs inline above the fold, disclosure for checks/escape/source. Footer variants: decision = recommended-outcome verb + "Went differently" menu + Skip; plain = Done + Skip + overflow (Revisit); target = Got it + Map + Clear target. Target body: GET header + icon, for-member line, effect, acquisition, collapsible PATH (4 rows + "· N more"), path step rows checkable via normal step disposition.
- [ ] `OverlayView`: title becomes breadcrumb ("Now ▸ \(area)"); `currentTab`, `walkthroughNowCard`, `encounterHUD`, `levelPlanCard` (dead), `factSection` deleted; `case .current: NowTabView()`. Keep dialogs/alerts, header icons, tab strip, off-theme `.bordered`/`.roundedBorder` replaced by themed controls.
- [ ] Verify build.

### Task 7: Route tab (B3) + StepDetailView

**Files:** Rewrite `mac/BG3Assistant/RouteTabView.swift`; Create `mac/BG3Assistant/StepDetailView.swift`

- [ ] Page state: `enum RoutePage { case list; case step(String); case gear(String, String) }`, slide transition, Back button on pushed pages.
- [ ] List: progress header (bar, "24/58 done", expandable Act 2 gate blockers — fixed pluralization); sticky phase headers (`LazyVStack(pinnedViews:)`); one full-row button per step (encounter icon in themed tints, `rowTitle` title, right `StatusChip`: now/ready/L*n*/later/revisit, chevron); focus action moves into StepDetailView; per-phase collapsed `◈ Pickups here · N` row expanding to pickup rows (`◯/✓ item → member · short source · ›`); bottom collapsibles Done (n) / Skipped (n) / Other pickups (n). Current-objective card removed.
- [ ] `StepDetailView(stepId:onBack:)`: full detail — chips, `FactRow`s, decision card with outcome buttons, incident/riskReward cards (kept from current file), Done/Skip/Revisit, "Set focus", source link.
- [ ] `RouteTabView` keeps `dependencyPresentation` logic, mapped to the new chip vocabulary; `railTag`/`RouteRailRow` deleted (7.5pt tags gone).
- [ ] Verify build.

### Task 8: Loadout tab (C2)

**Files:** Rewrite `mac/BG3Assistant/LoadoutTabView.swift`

- [ ] Party strip of active members (selected ring, `⚠` when no build) replaces the chevron rotator; one-line member summary with "edit ›" → `appState.plannerTab = .party`; embedded `RosterMemberEditor` removed from this tab.
- [ ] Doll grid: fixed-height (52pt) slot cells, 2-column paired slots + full-width ranged/extras; cell = slot icon, first item name (+"+N" when multiple), status glyph (`✓` equipped / `◯` get / `◈` targeted / `—` none). Header shows "n/m confirmed".
- [ ] Drawer at bottom: hover previews (`GearDetailView(showsActions: false)`), click pins (ring on cell, `showsActions: true`, all items of the slot listed), idle = one-line summary. `LoadoutSlot` enum kept.
- [ ] "Later" locked row (previously dead `laterGear`) restored as collapsible; "No reviewed pick" jargon replaced.
- [ ] Verify build.

### Task 9: Sweep + final verification

**Files:** All modified files

- [ ] Audit the four views for leftover raw `.orange/.red/.green` → theme roles; fonts < 9pt → scale tokens; remaining jargon ("RESOLVED", "reviewed", "requirement(s)", sheet/row references out of primary UI).
- [ ] `swift build -c release --scratch-path .build 2>&1 | tail -3` → `Build complete!`; `swift test 2>&1 | tail -3` → all pass.
- [ ] Manual QA notes for user: overlay layout at 420–520pt widths, hover drawer behavior over the game, target flow end-to-end.

## Self-review

Spec coverage: foundation → T1/T9; naming → T2; gear target model/behavior/path → T2/T3/T4/T6; Now A2 → T6; Route B3 + pickups → T3/T4/T7; Loadout C2 + drawer/hover/Later → T5/T8; quick wins → T5 (AsyncImage), T6 (dead code, off-theme controls), T7 (pluralization), T9 (sweep). Type consistency: `GearLogic.PathRow`/`Pickup` names used identically in T3/T4/T6/T7; `gearConflict` defined T5, consumed T5/T8. No placeholders: view tasks specify exact component contracts; logic tasks carry signatures + rules; test expectations enumerated in T3.
