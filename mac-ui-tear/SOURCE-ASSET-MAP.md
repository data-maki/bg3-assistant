# Source and asset map

## App shell and overlay

| Surface | Primary owner | State/action owner |
| --- | --- | --- |
| Menu-bar app, launch, Show Overlay, Open Planner, map, run switcher, BG3 launch, hide, settings, quit | [`BG3AssistantApp.swift`](../mac/BG3Assistant/BG3AssistantApp.swift#L41) | [`AppState+Overlay.swift`](../mac/BG3Assistant/AppState+Overlay.swift#L4), [`AppState+Persistence.swift`](../mac/BG3Assistant/AppState+Persistence.swift#L58) |
| Planner shell, header actions, primary tabs, screenshot permission alert | [`OverlayView.swift`](../mac/BG3Assistant/OverlayView.swift#L3) | [`AppState.swift`](../mac/BG3Assistant/AppState.swift#L41) |
| Minimal/focus/reference cards, context menu, shortcuts, completion menu | [`PeekCardView.swift`](../mac/BG3Assistant/PeekCardView.swift#L4) | [`AppState+Overlay.swift`](../mac/BG3Assistant/AppState+Overlay.swift#L4), [`AppState.swift`](../mac/BG3Assistant/AppState.swift#L519) |
| Window level, click behavior, drag/anchor, debug capture | [`OverlayPanelController.swift`](../mac/BG3Assistant/OverlayPanelController.swift#L64) | [`OverlayMetrics.swift`](../mac/BG3Assistant/OverlayMetrics.swift#L6) |
| Tab and density enums | [`BG3Models.swift`](../mac/BG3Assistant/BG3Models.swift#L930) | [`AppState.swift`](../mac/BG3Assistant/AppState.swift#L41) |
| Color, typography, glass, status chips, buttons, inset cards | [`AssistantGlassStyle.swift`](../mac/BG3Assistant/AssistantGlassStyle.swift#L3) | — |

## Onboarding

| Surface/option | Primary owner | Behavior/data owner |
| --- | --- | --- |
| Step order, titles, descriptions, fresh vs mid-run | [`Onboarding.swift`](../mac/BG3Assistant/Onboarding.swift#L22) | [`AppState+Onboarding.swift`](../mac/BG3Assistant/AppState+Onboarding.swift#L6) |
| Welcome fork | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L157) | [`AppState+Onboarding.swift`](../mac/BG3Assistant/AppState+Onboarding.swift#L31) |
| Difficulty and Explorer restriction | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L174) | [`ManualBuild.swift`](../mac/BG3Assistant/ManualBuild.swift#L5) |
| Full route vs next three tasks | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L243) | [`ManualBuild.swift`](../mac/BG3Assistant/ManualBuild.swift#L48) |
| Gemma, Qwen, OpenRouter, model install, Keychain status | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L80) | [`AIProvider.swift`](../mac/BG3Assistant/AIProvider.swift#L3), [`AppState+AIProvider.swift`](../mac/BG3Assistant/AppState+AIProvider.swift#L3) |
| Party and level selection | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L320) | [`PartyRosterRow.swift`](../mac/BG3Assistant/PartyRosterRow.swift#L3), [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L418) |
| Act and landmark catch-up | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L364) | [`Onboarding.swift`](../mac/BG3Assistant/Onboarding.swift#L135), [`AppState+Onboarding.swift`](../mac/BG3Assistant/AppState+Onboarding.swift#L44) |
| Ready screen and login-item choice | [`OnboardingView.swift`](../mac/BG3Assistant/OnboardingView.swift#L460) | [`AppState+Onboarding.swift`](../mac/BG3Assistant/AppState+Onboarding.swift#L72), [`LoginItem.swift`](../mac/BG3Assistant/LoginItem.swift#L1) |

## Planner screens and actions

| Screen | Primary owner | Related behavior |
| --- | --- | --- |
| Now briefing, More disclosure, target/later-act/route-complete variants | [`NowTabView.swift`](../mac/BG3Assistant/NowTabView.swift#L6) | [`AppState+Goal.swift`](../mac/BG3Assistant/AppState+Goal.swift#L7), [`AppState.swift`](../mac/BG3Assistant/AppState.swift#L479) |
| Route list, All/Core/Equipment filters, archived groups, gear rows | [`RouteTabView.swift`](../mac/BG3Assistant/RouteTabView.swift#L15) | [`AppState+Route.swift`](../mac/BG3Assistant/AppState+Route.swift#L8), [`RunSafety.swift`](../mac/BG3Assistant/RunSafety.swift#L1) |
| Route-step detail, focus, outcome, skip/revisit | [`StepDetailView.swift`](../mac/BG3Assistant/StepDetailView.swift#L4) | [`AppState.swift`](../mac/BG3Assistant/AppState.swift#L479) |
| Party landing, nested navigation, reset and roster-status confirmations | [`PartyTabView.swift`](../mac/BG3Assistant/PartyTabView.swift#L5) | [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L13) |
| Member name, level, reviewed build, comparison, reset | [`PartyMemberDetailView.swift`](../mac/BG3Assistant/PartyMemberDetailView.swift#L3) | [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L191) |
| Roster management | [`PartySetupView.swift`](../mac/BG3Assistant/PartySetupView.swift#L3) | [`PartyRosterRow.swift`](../mac/BG3Assistant/PartyRosterRow.swift#L3) |
| Ability recipe, applied boosts, source ledger | [`PartyAbilityRecipeView.swift`](../mac/BG3Assistant/PartyAbilityRecipeView.swift#L3) | [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L349) |
| Manual point buy, class timeline, subclass/feat/spell choices | [`ManualBuildPlannerView.swift`](../mac/BG3Assistant/ManualBuildPlannerView.swift#L3) | [`ManualBuild.swift`](../mac/BG3Assistant/ManualBuild.swift#L69), [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L217) |
| Public-URL build import and replacement confirmation | [`BuildImportView.swift`](../mac/BG3Assistant/BuildImportView.swift#L3) | [`BuildImportService.swift`](../mac/BG3Assistant/BuildImportService.swift#L1), [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L30) |
| Loadout character strip, slot grid, empty state | [`LoadoutTabView.swift`](../mac/BG3Assistant/LoadoutTabView.swift#L6) | [`GearLogic.swift`](../mac/BG3Assistant/GearLogic.swift#L1), [`GearPresentation.swift`](../mac/BG3Assistant/GearPresentation.swift#L1) |
| Gear detail, target, equipped state, conflict, alternate pick, map | [`GearDetailView.swift`](../mac/BG3Assistant/GearDetailView.swift#L7) | [`AppState+GearTarget.swift`](../mac/BG3Assistant/AppState+GearTarget.swift#L30), [`AppState+Party.swift`](../mac/BG3Assistant/AppState+Party.swift#L489) |
| Act 1 active ledger, Act 2/3 preview, equipment review, consequences, advance gate | [`ActTabView.swift`](../mac/BG3Assistant/ActTabView.swift#L3) | [`AppState+Acts.swift`](../mac/BG3Assistant/AppState+Acts.swift#L1) |
| Chat context, scope, quick prompts, messages, sources, screenshot preview | [`ChatTabView.swift`](../mac/BG3Assistant/ChatTabView.swift#L5) | [`AppState+Chat.swift`](../mac/BG3Assistant/AppState+Chat.swift#L4), [`AssistantAIClient.swift`](../mac/BG3Assistant/AssistantAIClient.swift#L1) |
| Provider, overlay, login, runs, support, legal, diagnostics | [`SettingsView.swift`](../mac/BG3Assistant/SettingsView.swift#L4) | [`RunStore.swift`](../mac/BG3Assistant/RunStore.swift#L4), [`AppState+Persistence.swift`](../mac/BG3Assistant/AppState+Persistence.swift#L58) |

## Runtime assets

| Asset | Used by | What it controls |
| --- | --- | --- |
| [`Resources/twilight-cleric.webp`](../Resources/twilight-cleric.webp) | [`PetSpriteView.swift`](../mac/BG3Assistant/PetSpriteView.swift#L4), [`PetAnimationModel.swift`](../mac/BG3Assistant/PetAnimationModel.swift#L4) | Assistant sprite sheet, frame coordinates, animation states |
| [`Resources/CompanionPortraits/`](../Resources/CompanionPortraits/) | [`PartyRosterRow.swift`](../mac/BG3Assistant/PartyRosterRow.swift#L91) | Astarion, Shadowheart, Lae'zel, Gale, Wyll, Karlach, and other portrait art |
| [`Resources/ItemIcons/`](../Resources/ItemIcons/) | [`GearDetailView.swift`](../mac/BG3Assistant/GearDetailView.swift#L126) | Bundled loadout and gear icons |
| [`data/item_icons.json`](../data/item_icons.json) | guide export plus `GearItemIcon` | Item-key to icon metadata |
| [`Resources/AppIcon.icns`](../Resources/AppIcon.icns), [`Resources/AppIcon.png`](../Resources/AppIcon.png) | [`Info.plist`](../Resources/Info.plist) | Dock/Finder app icon |
| [`Resources/Data/guide-bundle.json`](../Resources/Data/guide-bundle.json) | [`GuideRepository.swift`](../mac/BG3Assistant/GuideRepository.swift#L9) | Released route, walkthrough, build, gear, and item-catalog snapshot |
| [`BG3SpellCatalog.generated.swift`](../mac/BG3Assistant/BG3SpellCatalog.generated.swift#L5) | [`ManualBuild.swift`](../mac/BG3Assistant/ManualBuild.swift#L180) | Class spell and cantrip options in manual builds |
| [`Resources/PrivacyInfo.xcprivacy`](../Resources/PrivacyInfo.xcprivacy), [`Resources/BG3HonorAssistant.entitlements`](../Resources/BG3HonorAssistant.entitlements) | packaging/runtime | Privacy declaration and macOS capabilities |
| [`Resources/THIRD_PARTY_NOTICES.md`](../Resources/THIRD_PARTY_NOTICES.md) | [`SettingsView.swift`](../mac/BG3Assistant/SettingsView.swift#L137) | Legal & Credits disclosure |

## Source data that changes visible guidance

| Data | UI affected |
| --- | --- |
| [`data/act1_walkthrough.json`](../data/act1_walkthrough.json), [`data/act3_walkthrough.json`](../data/act3_walkthrough.json) | Now, Route, step detail, decisions, deadlines, catch-up landmarks |
| [`data/act1_route.json`](../data/act1_route.json), [`data/act3_route.json`](../data/act3_route.json) | Route dependencies, areas, minimum level, act gates |
| [`data/gear/`](../data/gear/) | Loadout slots, Act equipment review, pickup rows |
| [`data/build_overview.tsv`](../data/build_overview.tsv), [`data/build_levels.tsv`](../data/build_levels.tsv), [`data/build_ability_targets.json`](../data/build_ability_targets.json) | Reviewed-build comparison, levels, abilities, class guidance |
| [`data/act1_decisions.json`](../data/act1_decisions.json) | Completion outcome menus and irreversible-decision copy |
| [`data/act1_timed_events.json`](../data/act1_timed_events.json), [`data/act3_timed_events.json`](../data/act3_timed_events.json) | Deadlines, lockouts, unresolved consequences |

## Screenshot and packaging tooling

| File | Purpose |
| --- | --- |
| [`scripts/macos/build-app.sh`](../scripts/macos/build-app.sh) | Builds the local app bundle and copies runtime resources |
| [`scripts/macos/capture-readme.sh`](../scripts/macos/capture-readme.sh) | Seeds a deterministic run and captures the five primary marketing tabs |
| [`scripts/macos/build-app-store-screenshots.sh`](../scripts/macos/build-app-store-screenshots.sh) | Frames the primary captures for App Store artwork |
| [`scripts/macos/render-app-store-screenshot.swift`](../scripts/macos/render-app-store-screenshot.swift) | Native AppKit renderer for App Store text/layout |
| [`docs/images/`](../docs/images/) | Existing README captures and product-tour GIF |
| [`docs/app-store/screenshots/`](../docs/app-store/screenshots/) | Existing framed App Store screenshots |
