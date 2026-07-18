# First-Run Onboarding — Design

Date: 2026-07-18
Status: implemented alongside this doc (autonomous session; approach and
trade-offs recorded here in lieu of an interactive design review).

## Problem

A first-time user who installs the assistant sees only a menu-bar shield.
The overlay never appears until BG3 is running *and* the guide is loaded,
so nothing explains what the app does, how the peek card works, that
Option-Space is a hold-to-peek hotkey, that the card is draggable, that
party setup drives all advice, or that the OpenRouter key is optional.

## Approaches considered

1. **Separate welcome window (NSWindow wizard).** Familiar pattern, but it
   breaks the app's single-surface model (everything lives in the overlay
   panel) and teaches the user in a surface they will never see again.
2. **Coach-mark spotlight tour over the live planner.** Highest fidelity,
   but requires anchored popovers over a borderless non-activating NSPanel
   with custom layout — brittle, and most targets (peek card, planner
   tabs) cannot be shown simultaneously anyway.
3. **Paged tour card rendered by the overlay itself (chosen).** The
   overlay panel gains a third mode: `onboarding` > `planner` > `peek`.
   Minimal surface change (one branch in `OverlayView`, one size case in
   `OverlayMetrics`), reuses the panel infrastructure (drag, glass style),
   the step model is pure logic and testable without XCTest, and the final
   step can deep-link into the real Party/Settings tabs.

## Design

### Components

- **`Onboarding.swift`** (Foundation-only, standalone-testable):
  `OnboardingStep: Int, CaseIterable` — `welcome`, `peek`, `planner`,
  `party`, `chat`. Each step exposes `title`, `intro`, `facts`
  (`OnboardingFact` = glyph + semantic role + text), `primaryActionTitle`,
  and an optional `secondaryAction` (`openParty` / `openSettings`).
  Navigation helpers: `next`, `previous`, `isFirst`, `isLast`.
  `OnboardingStep.version = 1` — bump to re-show the tour after major UX
  changes.
- **`OnboardingView.swift`**: the card. Pet sprite + draggable header,
  step title/intro, `FactRow`s, progress dots, footer (`Skip tour` /
  `Back` / primary + secondary actions). Styled with `BG3Theme` and
  `assistantGlassSurface` like the planner.
- **`AssistantSettings.onboardingSeenVersion: Int?`** — optional so the
  synthesized decoder accepts existing settings rows (missing key → nil);
  legacy `migrating()` leaves it nil, so pre-existing installs see the
  tour once and never again after finishing or skipping.
- **`AppState`**: `@Published onboardingStep: OnboardingStep?` (non-nil =
  tour active, initialized from stored settings), `advanceOnboarding()`,
  `regressOnboarding()`, `finishOnboarding(opening:)` (persists the seen
  version, dismisses, optionally opens Party/Settings; skip uses the same
  path so the tour never nags), `replayOnboarding()` (Settings button).
  `start()` force-shows the overlay when the tour is active so the
  welcome appears immediately on first launch, before BG3 runs.
- **`OverlayMetrics.panelSize(onboarding:)`** — a dedicated card size
  (~430–520 × 470–540 pt, scaled from the reference frame) independent of
  tab/density so Option-Space or menu actions cannot resize mid-tour.
- **`SettingsView`**: "Replay Welcome Tour" button in General.

### Flow

Fresh install → settings row absent → `onboardingStep = .welcome` →
`start()` sets `forceOverlay` → panel shows the tour card with BG3 closed.
`Continue` pages through; `Skip tour` or the final `Start Adventuring`
persists `onboardingSeenVersion` and collapses to the peek card (kept
visible for continuity). "Open Party Tab" / "Open Settings" finish the
tour into the planner on that tab. Quitting mid-tour re-shows it next
launch (only finishing persists).

### Dev hook

`BG3_ASSISTANT_DEBUG_TAB` suppresses the tour (so tab verification stays
deterministic) unless its value is `onboarding`, which forces the tour —
this is also the deterministic launch path for verification.

## Testing

- Standalone `swiftc` runner (no XCTest on this machine): step-model
  invariants, `AssistantSettings` decode compatibility (legacy JSON
  without the flag; unknown keys), `RunStore` settings round-trip through
  real SQLite in a temp dir, `OverlayMetrics` onboarding sizing bounds.
- Mirrored `OnboardingTests.swift` XCTest file for CI.
- Live app runs against isolated `BG3_ASSISTANT_STATE_DIR`s, observed via
  CGWindowList owner/bounds (no TCC needed): fresh dir → onboarding-sized
  panel; relaunch unfinished → still shows; seeded completed settings →
  no overlay panel; legacy row → tour shows and density survives;
  `BG3_ASSISTANT_DEBUG_TAB=route` → route-sized panel (tour suppressed).
