# Windows UI/UX Replica Plan

Status: proposed replacement for the UI portions of `implementation-plan.md`

Reference: `mac-ui-tear/` at commit `4719b56`

## Decision

Keep the existing WPF application, controller, domain models, persistence, Windows
overlay integration, and OpenRouter client. Rebuild the visible WPF layer to match
the macOS app screen-for-screen.

This is a shell rebuild, not a theme pass. The current Windows app exposes many of
the right commands and data, but its UI structure is a conventional 1100 x 760
desktop form. The macOS product is a compact 420-520 px overlay with a BG3-styled
frame, card navigation, state-specific onboarding, nested detail screens, portraits,
gear artwork, and in-panel confirmations.

Do not rewrite `BG3HonorAssistant.Core`, `BG3HonorAssistant.Infrastructure`, or
`BG3HonorAssistant.Windows` for visual parity. Add small controller adapters only
when an existing domain operation is not yet reachable from a replica screen.

## Two-source oracle

Every Windows screen must be implemented from both Mac references:

1. `mac-ui-tear/` defines what the screen and each visible state look like.
2. `mac/BG3Assistant/` defines what every control does, which state it reads, which
   action it calls, what confirmation it requires, and what is persisted.

Do not reproduce a screenshot with placeholder behavior. Do not infer behavior from
button labels when the Swift implementation exists.

For each screenshot/state, the implementation sequence is:

1. Find the state in `mac-ui-tear/SCREEN-INVENTORY.md`.
2. Follow its owners in `mac-ui-tear/SOURCE-ASSET-MAP.md`.
3. Read the complete Swift view plus its referenced `AppState`, model, and helper
   functions under `mac/BG3Assistant/`.
4. Map those functions to the existing Windows controller/Core operation.
5. When Windows is missing an operation, write the C# equivalent with the same
   inputs, state transition, confirmation, persistence, and user-visible result.
6. Apply only the approved Windows substitutions and exclusions listed below.

The macOS source is the behavioral oracle. Existing Windows behavior should be
preserved only when it is platform-specific or already equivalent to the Mac
behavior.

## Mac-to-Windows function map

| Product area | Read in `/mac` | Windows implementation target |
| --- | --- | --- |
| Shell and overlay | `BG3AssistantApp.swift`, `OverlayView.swift`, `PeekCardView.swift`, `OverlayMetrics.swift`, `AppState+Overlay.swift` | `App.xaml.cs`, `MainWindow`, `OverlayWindow`, `OverlayCoordinator`, `OverlayWindowService` |
| Onboarding, runs, and settings | `OnboardingView.swift`, `Onboarding.swift`, `AppState+Onboarding.swift`, `SettingsView.swift`, `AppState+Persistence.swift` | `OnboardingView`, `SettingsView`, `AssistantController`, `RunRepository`, Windows startup and credentials adapters |
| Now and Route | `NowTabView.swift`, `RouteTabView.swift`, `StepDetailView.swift`, `AppState+Goal.swift`, `AppState+Route.swift`, `RunSafety.swift` | `NowView`, `RouteView`, `AssistantController`, existing Core route/current-goal rules |
| Party, builds, abilities, and loadout | `PartyTabView.swift`, `PartyMemberDetailView.swift`, `PartySetupView.swift`, `PartyAbilityRecipeView.swift`, `ManualBuildPlannerView.swift`, `BuildImportView.swift`, `LoadoutTabView.swift`, `GearDetailView.swift`, `AppState+Party.swift`, `AppState+GearTarget.swift` | `PartyView`, `LoadoutView`, `AssistantController`, existing Core party/manual-build/gear rules, existing build importer |
| Act and Chat | `ActTabView.swift`, `ChatTabView.swift`, `AppState+Acts.swift`, `AppState+Chat.swift`, `AssistantAIClient.swift` | `ActView`, `ChatView`, `AssistantController`, existing Core act/chat prompt rules and OpenRouter client |

Required platform substitutions:

- `LoginItem.swift` behavior maps to `StartupTaskService`.
- macOS Keychain behavior maps to `CredentialStore`.
- AppKit URL/game launching maps to `GameLauncher`.
- `OverlayPanelController.swift` placement/activation behavior maps to
  `OverlayWindowService`.
- Local-model and capture/audio functions have no Windows equivalent and must be
  removed with the surrounding layout reflowed.

## Product scope

Copy from macOS:

- Panel dimensions, hierarchy, navigation, spacing, typography, colors, borders,
  shadows, cards, chips, disclosures, buttons, empty states, and confirmations.
- Fresh and mid-run onboarding.
- Minimal, Focus, and Reference overlay densities.
- Now, Route, Party, Loadout, Act, Chat, and Settings.
- Nested route, character, build, ability, gear, roster, and run flows.
- Existing shared companion, portrait, item, and build-option artwork.

The Mac sizes and BG3 visual language are approved product decisions, not starting
points for a Windows reinterpretation. Do not replace them with Fluent/Mica layouts,
larger desktop-form spacing, a Windows sidebar, or conventional resizable-window
proportions.

Intentional Windows differences:

- No screen capture, screenshot attachment, screen sharing, or screenshot prompt.
- No microphone, audio, speech, or dictation controls.
- No Gemma, Qwen, Ollama, model downloads, or local-model settings.
- OpenRouter is the only optional AI provider and uses Windows Credential Manager.
- Windows tray, startup, game-window detection, and Steam launch remain native.
- Act 2 continues to show the existing guide data-gap message.

## Current Windows diagnosis

| Area | Current Windows UI | Required replica |
| --- | --- | --- |
| Shell | 1100 x 760 normal window with a large title bar, run picker, text box, and stock tabs | Compact adaptive 420-520 px overlay; pet, breadcrumb, four icon actions, and five-item capsule navigation |
| Theme | Seven flat brushes, stock WPF buttons, GroupBox, ComboBox, DataGrid, and TabControl | BG3 ink/umber/bronze/gold palette, dual bronze frame, inset cards, serif headings, compact action buttons, chips, and disclosures |
| Onboarding | One generic panel and one ComboBox reused for every step | Dedicated selection cards and editors for each fresh/mid-run state, progress capsules, and Mac-matching copy |
| Now | Large heading, one plain panel, and eight equal buttons | Compact briefing card, fact rows, More disclosure, and anchored Done/Skip actions |
| Route | Functional two-column desktop master/detail | Single-column grouped route cards with filters; selected step replaces the list with a breadcrumb detail screen |
| Party | Read-only DataGrid with four buttons | Portrait cards, active/camp status, nested character pages, reviewed/manual builds, abilities, and roster management |
| Loadout | Build browser and build import form | Character strip plus two-column equipment-slot grid; build work moves into Party/character screens |
| Act | Text counts and a plain equipment list | Three-act segmented ledger, act preview card, illustrated equipment review rows, consequences, and gate state |
| Chat | Desktop RichTextBox and toolbar | Compact context chips, conversation cards, bottom quick prompts and composer; text only on Windows |
| Settings | Stock GroupBoxes plus a separate Diagnostics tab | Mac card stack; OpenRouter, General, Runs, Support, Legal, and Diagnostics disclosures in one screen |
| Overlay | Correct three densities and pet behavior, generic visual treatment | Preserve behavior and copy the exact Mac frame, type, spacing, shortcuts, and context menu |
| Dialogs | Native MessageBox confirmations | BG3-styled in-panel confirmation cards matching the captured states |

## Target shell

```text
┌──────────────────────────────────────────┐  420-520 px
│ [pet]  Now › Ravaged Beach   [map][chat] │
│                              [gear][⌄]   │
│ ┌ NOW ─ ROUTE ─ PARTY ─ LOADOUT ─ ACT ┐ │
│ └──────────────────────────────────────┘ │
│                                          │
│  active screen or nested detail          │
│  cards scroll inside the fixed panel     │
│                                          │
│  [contextual primary actions]            │
└──────────────────────────────────────────┘
```

The frame remains an owned WPF overlay window. Navigation changes content inside
the frame; it must not open ordinary child windows for route, character, gear, or
build details.

## Exact Mac sizing

Port `OverlayMetrics.swift` into Windows logical device-independent pixels. Use the
same formulas, bounds, and game-window-relative scale; let WPF perform only the
required monitor DPI conversion.

| Surface | Mac size to preserve |
| --- | --- |
| Minimal companion | 126 x 98 |
| Focus overlay | Width 430-500; height 164-182 |
| Reference overlay | Width 430-500; height 184-206 |
| Expanded planner width | 420-520 |
| Now | Height 410-440 normally; 550-640 with More expanded |
| Party | Height 540-620 |
| Loadout | Height 590-680 |
| Route, Act, Chat, Settings | Height 550-640 |
| Onboarding | Width 430-520; Welcome 350-390; Difficulty 560-640; other steps 470-540 |

Preserve the Mac 8 px outer padding, 10 px planner padding, 16 px outer radius,
8-9 px inset radii, compact tab/header heights, and per-screen internal scrolling.
Do not add a Windows title bar, resize grip, status bar, or unused minimum window
space.

## Minimal WPF structure

Do not introduce an MVVM framework or replace `AssistantController`.

```text
BG3HonorAssistant.App/
  App.xaml                         global resources and composition
  Application/
    AssistantController.cs        product-operation boundary
  Shell/
    MainWindow.xaml               frame, header, navigation, content host
    MainWindow.xaml.cs            navigation and refresh orchestration
  UI/
    Theme.xaml                     exact colors, type, spacing, control styles
    AssetImage.cs                  shared portrait/item/build asset lookup
  Screens/
    Now/                           view plus screen-owned behavior
    Route/                         list/detail view plus route actions
    Party/                         nested member/roster/ability/build components
    Loadout/                       character strip, slots, gear detail
    Act/                           ledger, review, and transition actions
    Chat/                          typed OpenRouter states and composer
    Settings/                      runs, provider, support, diagnostics
  Components/
    Onboarding/                    all onboarding page templates
    Dialogs/                       shared confirmation surfaces
  Overlay/                         minimal/focus/reference window and coordinator
```

Each view code-behind only forwards typed UI events. Rendering, local interaction
state, and controller calls live in the adjacent screen-owned `MainWindow` partial.
Keep persistence and product commands in `AssistantController`. This keeps the
shell small without adding framework ceremony or a parallel state model.

## Visual foundation

Port the macOS design tokens literally:

- Ink `#0E0C09`, umber `#2E2116`, bronze `#8C5224`, bright bronze `#9C693B`.
- Gold `#C7A15E`, parchment `#F0E3C2`, muted parchment `#B8AB8F`.
- Success `#619E7A`, warning `#C77840`, caution `#B8964D`, danger `#C75247`.
- Body: Segoe UI Variable Text at Windows-equivalent 12 px scale.
- Serif titles/overlines: Georgia, matching the Mac serif hierarchy.
- Outer radius 16 px, inset radius 8-9 px, dual bronze/gold border, dark diagonal
  panel gradient, restrained black shadow.
- Compact controls: 9-13 px labels/body, 17 px page titles, 5-10 px gaps, 6-10 px
  internal padding.

Implement the Mac glass appearance with a WPF gradient and opacity first. Do not
block the replica on acrylic/Mica; those effects are less important than matching
the hierarchy, dimensions, borders, and contrast.

The existing MSBuild links already provide the shared guide, pet sprite, 11
portraits, 51 item icons, and build-option icons. Change their development-output
copy behavior where needed so the WPF views can actually load them before publish.

## Shared cross-platform asset policy

The repository-root `Resources/` directory is the canonical cross-platform asset
source. Both macOS and Windows must load and package from it; do not create
platform-specific edited copies.

| Canonical shared asset | Windows use |
| --- | --- |
| `twilight-cleric.webp` | Identical sprite atlas, frame coordinates, idle/look/jump behavior, and companion presentation |
| `CompanionPortraits/` (11 files) | Party, character detail, roster, and loadout character strip |
| `ItemIcons/` (51 files) | Loadout slots, gear detail, route pickups, and Act equipment review |
| `BuildOptionIcons/` (697 files) | Manual build class, feat, spell, cantrip, subclass, and choice rows |
| `AppIcon.png` (1024 x 1024) | Source artwork for Windows app/package icon sizes |
| `Data/guide-bundle.json` | Same released route, walkthrough, build, gear, and item metadata |
| `THIRD_PARTY_NOTICES.md` | Same Legal & Credits content |

Implementation rules:

1. Keep MSBuild `Content` links pointed at the repository-root `Resources/` paths.
2. Use `CopyToOutputDirectory="PreserveNewest"` and
   `CopyToPublishDirectory="PreserveNewest"` for every runtime visual asset.
3. Resolve asset names through one Windows `AssetImage` helper without altering,
   recoloring, redrawing, or recompressing the source art.
4. Use the same rarity borders, portrait cropping, sprite-frame coordinates, and
   disabled/selected opacity treatment defined by the Swift views.
5. If a Mac view uses an SF Symbol, reproduce the small control glyph in Windows;
   SF Symbols are macOS system glyphs rather than reusable repository assets.

## Implementation order

### Phase 1 - Frame, theme, and overlay

Estimate: 2-3 engineer-days

1. Replace stock WPF control styling with `Theme.xaml` and the five shared replica
   controls.
2. Replace the large desktop header and `TabControl` with `PlannerShell`.
3. Port the exact size and scaling rules from `OverlayMetrics.swift`.
4. Restyle Minimal, Focus, and Reference overlays without changing their existing
   placement, activation, drag, or pet-animation behavior.
5. Wire the shared Mac assets into development and published Windows output.

Screenshot targets: 13, 14, 16, 46, 47.

Mac function targets: `BG3AssistantApp.swift`, `OverlayView.swift`,
`PeekCardView.swift`, `OverlayMetrics.swift`, `AppState+Overlay.swift`, and
`AssistantGlassStyle.swift`.

### Phase 2 - Onboarding

Estimate: 2-3 engineer-days

1. Replace the generic ComboBox wizard with Mac-style choice cards.
2. Implement fresh-run difficulty, spoiler, optional OpenRouter, party, and ready
   screens.
3. Implement mid-run Act 1/2/3 catch-up and landmark selection.
4. Keep Explorer disabled and explain why.
5. On Windows, replace the Mac provider screen with two cards only: `Guide only`
   and `OpenRouter`; remove every local-model/download state.

Screenshot targets: 01-12 and 51-56, with the provider adaptation above.

Mac function targets: `OnboardingView.swift`, `Onboarding.swift`,
`AppState+Onboarding.swift`, `PartyRosterRow.swift`, `AppState+Party.swift`, and
`LoginItem.swift`. Read the local-provider functions only to identify and omit
their controls and state.

### Phase 3 - Now and Route

Estimate: 3-4 engineer-days

1. Recompose Now into status chips, objective title, icon-gutter fact rows, More
   disclosure, and bottom-anchored Done/Skip actions.
2. Recompose Route into grouped single-column cards with All/Core/Equipment
   segmented filters, progress, gate, deadline, spoiler-light, and archive states.
3. Make route selection navigate inside the panel to a breadcrumb detail screen.
4. Preserve focus, outcome, skip, revisit, source, and gear-target actions.

Screenshot targets: 16-22 and 57.

Mac function targets: `NowTabView.swift`, `RouteTabView.swift`,
`StepDetailView.swift`, `AppState+Goal.swift`, `AppState+Route.swift`,
`AppState.swift` completion/disposition actions, and `RunSafety.swift`.

### Phase 4 - Party, builds, abilities, and loadout

Estimate: 6-8 engineer-days

1. Replace the Party DataGrid with portrait cards and a roster-management footer.
2. Add the nested character page with name, level, status, abilities, reviewed
   build, comparison, manual build, and reset confirmation.
3. Move reviewed-build assignment and public URL import out of Windows Loadout and
   into the character/build flow where they exist on Mac.
4. Expose the existing manual-build model as the level 1-12 planner.
5. Rebuild Loadout as a character strip plus equipment-slot grid.
6. Add gear detail, alternatives, target, equipped, ownership conflict, map, and
   source actions using the linked item artwork.

Screenshot targets: 23-36, 59, and 60.

Mac function targets: `PartyTabView.swift`, `PartyMemberDetailView.swift`,
`PartySetupView.swift`, `PartyRosterRow.swift`, `PartyAbilityRecipeView.swift`,
`ManualBuildPlannerView.swift`, `BuildImportView.swift`, `LoadoutTabView.swift`,
`GearDetailView.swift`, `AppState+Party.swift`, and `AppState+GearTarget.swift`.

### Phase 5 - Act, Chat, Settings, and dialogs

Estimate: 3-4 engineer-days

1. Rebuild Act as the three-act ledger with previews, equipment review, consequence
   sections, advance gate, and final lock state.
2. Rebuild Chat with context chips, empty/loading/answer/error states, quick prompts,
   source links, and a bottom composer.
3. Omit the Mac microphone button and screenshot status/attachment row entirely.
4. Rebuild Settings as Mac-style sections and move Diagnostics into a disclosure.
5. Keep only OpenRouter key/model controls; omit the provider picker and all local
   model rows.
6. Replace native confirmations for new run, reset character, destructive route
   actions, and build replacement with the in-panel confirmation component.

Screenshot targets: 37-45, 48-50, and 58.

Mac function targets: `ActTabView.swift`, `ChatTabView.swift`, `SettingsView.swift`,
`AppState+Acts.swift`, `AppState+Chat.swift`, `AppState+Persistence.swift`,
`RunStore.swift`, and `AssistantAIClient.swift`. Do not port the screenshot,
microphone, or local-provider branches.

## Screen-and-function completion rule

There is no new automated-test milestone in this UI plan. A screen is implementation
complete only when:

1. Its XAML covers the corresponding screenshot's frame, hierarchy, typography,
   spacing, artwork, controls, and state variants.
2. Every interactive control is mapped to the equivalent Swift action owner.
3. The Windows action produces the same state transition, confirmation, persistence,
   navigation, disabled state, and user-visible result.
4. Platform-specific behavior uses the named Windows substitution rather than a
   Mac-only API.
5. Intentional Windows omissions leave no blank gaps, dead controls, or unreachable
   state.

The `mac-ui-tear/SCREEN-INVENTORY.md` sequence is the build checklist. When a
Windows machine is available, capture the same numbered states into a separate
`windows/evidence/ui-replica/` folder for the final human visual correction pass.
That future screenshot pass is for tuning, not a prerequisite for implementing the
replica from the existing Mac references.

## Files to preserve

- `Application/AssistantController*.cs` and the four-project architecture.
- Existing Core models and route/party/build/gear/act rules.
- SQLite, Credential Manager, OpenRouter, game detection, overlay placement, tray,
  startup, package, and Steam-launch services.
- Shared assets linked from the repository-root `Resources` directory.

## Files to replace or reduce

- Replace nearly all layout in `MainWindow.xaml`.
- Reduce `MainWindow.xaml.cs` to shell navigation and controller orchestration.
- Expand `App.xaml` into a small merged theme dictionary instead of seven generic
  brushes and stock control defaults.
- Replace the generic onboarding block at the bottom of `MainWindow.xaml`.
- Restyle `OverlayWindow.xaml` while keeping its proven window behavior.
- Remove the separate top-level Diagnostics tab.
- Remove the desktop-form run picker/name controls from the header.
- Stop using DataGrid and GroupBox as player-facing layout primitives.

## Estimate

One experienced WPF engineer: approximately 16-22 working days for the complete
59-state replica, assuming existing controller/domain operations are retained.

The fastest path is to build the shell and reusable visual primitives once, then
move through the screenshot inventory in order. Trying to incrementally decorate
the current desktop form would be faster for a few screens but slower overall
because Party, Loadout, onboarding, nested details, and Settings have the wrong
information architecture.
