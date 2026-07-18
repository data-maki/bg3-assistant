# Onboarding Intake Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 5-card fact tour with a run-intake wizard (fresh/mid-run fork, party+level, act catch-up), gate the login item on `onboardingCompleted`, add one-time hint bubbles, and move the OpenRouter key server-side so users never see it.

**Architecture:** The wizard stays a pure `OnboardingStep` model (branching by `OnboardingMode`) rendered by the overlay panel, mutating the run through existing AppState party/route APIs. Mid-run adoption writes a new `caughtUp` disposition into the walkthrough ledger; every "is it completed" projection treats it as done, the Route tab renders it distinctly, and the Python map backend round-trips it without data loss. AI features key off backend-reported availability (`/health.ai_available`) instead of a local Keychain key.

**Tech Stack:** SwiftUI/AppKit (swift-tools 6.0, XCTest via `swift test` in `mac/`), FastAPI + pydantic backend (`pytest` in `backend/`).

**Approved by user:** 2026-07-18 chat ("Implement your suggestions"), including backend-held key. Handoff buttons and the API-key tour card are removed; the "Assign honor builds" preset button is out of scope (no data-backed default build mapping exists).

---

### Task 1: Backend — AI availability in /health + key-free error copy

**Files:**
- Modify: `backend/app/models.py` (HealthResponse, ~line 456)
- Modify: `backend/app/main.py` (health(), import 428 copy)
- Test: `backend/tests/test_health_ai.py`

- [x] Test: health reports `ai_available` true when `OPENROUTER_API_KEY` set, false when empty (monkeypatch env + `get_settings.cache_clear()`).
- [x] `HealthResponse` gains `ai_available: bool = False`; `health()` sets it from `bool(get_settings().openrouter_api_key)`.
- [x] `import_custom_build` 428 detail no longer references Settings: `"AI build import is not available right now. Check that the assistant is up to date."`
- [x] Run `pytest backend/tests/test_health_ai.py -q` → pass. Commit.

### Task 2: caughtUp disposition — Swift semantics

**Files:**
- Modify: `mac/BG3Assistant/BG3Models.swift:3` (enum + helper)
- Modify: `mac/BG3Assistant/RunSafety.swift` (dependencyBlockers, routeConsequences)
- Modify: `mac/BG3Assistant/AppState.swift` (completedIds)
- Modify: `mac/BG3Assistant/AppState+Route.swift` (two `== .completed` sites)
- Modify: `mac/BG3Assistant/AppState+Persistence.swift:141` (completedSteps count)
- Modify: `mac/BG3Assistant/AppState.swift` `openActOneMap` walkthrough param: `mapValues { $0 == .caughtUp ? .completed : $0 }`
- Modify: `mac/BG3Assistant/RouteTabView.swift` (render "Caught up" label for `.caughtUp`)
- Test: `mac/Tests/BG3AssistantTests/RunSafetyTests.swift`

Semantics: `.caughtUp` = "resolved before the assistant arrived; assume the guide's recommended path". It satisfies `completion_required` AND `outcome_required` dependencies (no recorded outcome required), is excluded from route consequences, counts in `completedIds`/saved-run progress, and renders as "Caught up" (never "Done") in the Route tab.

```swift
enum CheckpointDisposition: String, Codable, CaseIterable {
    case pending, completed, skipped
    /// Bulk-marked by mid-run catch-up: resolved before the assistant was
    /// installed, assumed to follow the guide's recommended path.
    case caughtUp

    var countsAsCompleted: Bool { self == .completed || self == .caughtUp }
}
```

`RunSafety.dependencyBlockers`: `completion_required` → `status.countsAsCompleted`; `outcome_required` → `(status == .completed && outcomes match) || status == .caughtUp`. `routeConsequences`: `guard !state.countsAsCompleted`.

- [x] Tests first (caughtUp satisfies both dependency kinds; consequences ignore caughtUp; nextWalkthroughStep recommends first pending step after a caught-up block). `swift test --filter RunSafetyTests` → pass. Commit.

### Task 3: caughtUp round-trip in map backend

**Files:**
- Modify: `backend/app/stores.py` (`_run_state_from_snapshot`, `_merge_run_state_into_snapshot`)
- Test: `backend/tests/test_caught_up.py`

`_run_state_from_snapshot`: include `"caughtUp"` in the accepted set, mapping to `"done"` for the map vocabulary. `_merge_run_state_into_snapshot`: when writing `"completed"` for a step whose ORIGINAL snapshot value was `"caughtUp"`, preserve `"caughtUp"` (the map never distinguishes; only an explicit Swift-side write should upgrade it). Without this, any map-side edit erases every caught-up entry.

- [x] Test: snapshot with caughtUp steps → run state shows them done → merging a map write back preserves `caughtUp` and keeps new map-side completions as `completed`. `pytest backend/tests/test_caught_up.py -q` → pass. Commit.

### Task 4: Onboarding model rewrite (branching intake + catch-up logic)

**Files:**
- Rewrite: `mac/BG3Assistant/Onboarding.swift`
- Modify: `mac/BG3Assistant/RunStore.swift` (AssistantSettings: `onboardingCompleted: Bool?`, `seenHints: [String]?`)
- Rewrite: `mac/BG3Assistant/AppState+Onboarding.swift`
- Modify: `mac/BG3Assistant/AppState.swift` (mode/catch-up/login-toggle state; `onboardingCompleted`)
- Modify: `mac/BG3Assistant/AppState+Persistence.swift` (persistSettings)
- Modify: `mac/BG3AssistantApp.swift` (remove silent login-item auto-enable)
- Test: rewrite `mac/Tests/BG3AssistantTests/OnboardingTests.swift`

Model (pure, Foundation-only):

```swift
enum OnboardingMode { case fresh, midRun }

enum OnboardingStep: Int, CaseIterable {
    case welcome, party, catchUp, ready
    static let version = 2
    static func steps(for mode: OnboardingMode) -> [OnboardingStep] {
        mode == .midRun ? allCases : [.welcome, .party, .ready]
    }
    func next(for mode: OnboardingMode) -> OnboardingStep?      // index+1 in steps(for:)
    func previous(for mode: OnboardingMode) -> OnboardingStep?  // index-1
    func stepNumber(for mode: OnboardingMode) -> Int
    static func stepCount(for mode: OnboardingMode) -> Int
    // title/intro per step; ready keeps a short fact list (hotkey, map, chat)
}

enum CatchUp {
    /// Marks every pending step up to and including the landmark's owning
    /// step as caughtUp. Existing completed/skipped entries are preserved.
    static func ledger(
        markingThrough checkpointId: String,
        walkthrough: [WalkthroughStep],
        existing: [String: CheckpointDisposition]
    ) -> [String: CheckpointDisposition]?   // nil when no step owns the checkpoint
}
```

AppState flow: `chooseFreshRun()`/`chooseMidRun()` set mode + advance; `selectOnboardingAct(_:)` sets `run.selectedAct`, persists, `resetGuideContext()` + `loadRouteIfNeeded()`; `applyCatchUpAndAdvance()` writes the ledger via `CatchUp.ledger` and advances (nil selection = start of act, no marking); `finishOnboarding(completed:)` records `onboardingSeenVersion = 2`, sets `onboardingCompleted`, enables the login item **only** when `completed && onboardingEnableLoginItem`, lands on the collapsed peek card. `skipOnboarding()` → `finishOnboarding(completed: false)`. `replayOnboarding()` resets mode/selection and clears `seenHints`. `OnboardingHandoff` and the facts-deck content are deleted.

AppDelegate: delete the `BG3LoginItemConfigured` auto-enable block (existing installs keep whatever login-item state they already have; the wizard's final card owns enabling from now on).

- [x] Tests: branching navigation round-trips per mode; version == 2; catch-up ledger (inclusive marking, preserves existing, nil on unknown checkpoint, later steps untouched); settings round-trip incl. legacy decode (`onboardingCompleted`/`seenHints` nil). `swift test --filter OnboardingTests` → pass. Commit.

### Task 5: Wizard views

**Files:**
- Create: `mac/BG3Assistant/PartyRosterRow.swift` (row + status menu extracted from PartySetupView)
- Modify: `mac/BG3Assistant/PartySetupView.swift` (use extracted row)
- Rewrite: `mac/BG3Assistant/OnboardingView.swift`
- Modify: `mac/BG3Assistant/SettingsView.swift` (replay button label "Replay Tour & Hints")

Four cards sharing chrome (pet header, "SETUP · n of N" counter, skip ✕, progress dots, Back/primary footer):
1. **Welcome** — promise line + two option buttons (fresh honor run / already mid-run) + "Skip — explore with defaults" footer link. No Continue button; choosing advances.
2. **Party** — "Everyone's level" stepper (1–12, `setAllPartyLevels`), scrollable roster rows (reused component: Active/Camp/Unrecruited menus), live caption "Readiness and danger warnings key off level N." Continue.
3. **Catch-up** (mid-run only) — act picker (1/2/3, `selectOnboardingAct`), loading state while the act guide loads, checkpoint list (routeOrder-sorted, radio select, "Start of the act" row = nil), caption "N earlier steps will be marked caught up — kept distinct from steps you completed with me." Primary: "Catch Up & Continue".
4. **Ready** — summary facts (act, party level, caught-up count, Option-Space hotkey, map button, chat), login-item disclosure toggle ("Start at login so the assistant appears whenever BG3 opens", bound to `onboardingEnableLoginItem`, default on), primary "Start Adventuring" → `finishOnboarding(completed: true)`.

- [x] `swift build` clean; visual pass deferred to Task 7. Commit.

### Task 6: Hint bubbles

**Files:**
- Create: `mac/BG3Assistant/Hints.swift` (HintID + copy + bubble view)
- Modify: `mac/BG3Assistant/AppState.swift` (activeHint, seenHints, session cap, triggers)
- Modify: `mac/BG3Assistant/OverlayMetrics.swift` (`panelSize(hint:)` adds +52pt)
- Modify: `mac/BG3Assistant/OverlayPanelController.swift` (pass hint flag)
- Modify: `mac/BG3Assistant/OverlayView.swift` (bubble above content)
- Test: `mac/Tests/BG3AssistantTests/HintTests.swift`

```swift
enum HintID: String, CaseIterable {
    case peekBasics   // first refresh with gameDetected && collapsed
    case plannerMap   // first overlayExpanded == true
    case fightTools   // first assistantPhase == .preflight while collapsed
}
```

`maybeShowHint` guards: onboarding inactive, no active hint, `!combatCardPinned`, unseen, `!hintShownThisSession` (max one per session). Dismiss ([Got it] or any hint-tap) marks seen + persists. Triggers live in `refreshStatuses` (peekBasics, fightTools) and `overlayExpanded.didSet` (plannerMap). Bubble is a fixed 44pt row above the card inside the panel; the panel grows via the metrics flag so no layout squeezes.

- [x] Tests: copy completeness; settings round-trip; metrics adds height only when flagged, never during onboarding. `swift test --filter HintTests` → pass. Commit.

### Task 7: Swift AI availability replaces key UI

**Files:**
- Modify: `mac/BG3Assistant/BG3Models.swift:841` (BackendHealth `aiAvailable: Bool?`)
- Modify: `mac/BG3Assistant/AppState.swift` (`backendAIAvailable`; set in refreshStatuses; delete `openRouterKeyDraft`/`hasOpenRouterKey`/`openRouterKeyStatus`/`saveOpenRouterKey`/`removeOpenRouterKey`)
- Modify: `mac/BG3Assistant/AppState+Chat.swift:14` (gate on `backendAIAvailable`)
- Modify: `mac/BG3Assistant/AppState+Party.swift:36` (guard message: "AI build import is not available right now.")
- Modify: `mac/BG3Assistant/BuildImportView.swift` (delete key-entry section + save-key path; show unavailable note when `!backendAIAvailable`)
- Modify: `mac/BG3Assistant/SettingsView.swift` (delete "AI Features" section)
- Keep: `OpenRouterKeyStore` + `BackendProcessManager` env passing (existing installs' keys and dev overrides still work, invisibly; bundle `.env` in the backend root is the release path — `config.py` already loads it).

- [x] `swift build && swift test` clean; grep confirms no UI string mentions OpenRouter keys (the screenshot-consent alert copy stays, reworded to "the AI service"). Commit.

### Task 8: Full verification

- [x] `pytest backend/tests -q` all green.
- [x] `cd mac && swift test` all green.
- [x] Use the `verify` skill: build + launch with fresh `BG3_ASSISTANT_STATE_DIR` and `BG3_ASSISTANT_DEBUG_TAB=onboarding`; walk both wizard branches (fresh + mid-run/catch-up), confirm landing card, hint bubble on planner open, no key UI in Settings. Screenshot each card.
- [x] Commit any fixes; update `LEARNINGS.md` only if something non-obvious surfaced.

## Self-review notes
- Spec coverage: intake fork ✓, catch-up screens ✓, onboardingCompleted gate ✓, hints ✓, server-side key ✓, tour version bump ✓, map round-trip protection ✓.
- Deliberately out of scope (told to user): "Assign honor builds" preset (no default-build data), missables digest after catch-up (content work, fast-follow), earlier-act synthetic transitions (act ledger untouched; guidance only ever reads the selected act).
