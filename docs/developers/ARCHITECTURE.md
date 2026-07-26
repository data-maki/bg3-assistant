# Architecture

BG3 Overlay is a native menu-bar macOS app with an in-game SwiftUI/AppKit overlay. The macOS release runtime does not include or start Python, FastAPI, a localhost companion, or a project-hosted AI service. Swift reads a generated guide resource, owns run persistence, calls the user-selected AI provider, and opens the configured public map in the default browser.

## Product boundary

The app shows the current risk, recommended action, route progress, party and build guidance, equipment plans, act-transition checks, and guide-grounded chat. Progress, outcomes, party status, and equipment ownership change only when the player confirms them.

It is not a BG3 mod. It does not read game memory or saves, edit game files, automate input, infer progress, take periodic screenshots, or record gameplay. With Screen Recording permission, OpenRouter chat may attach one player-visible BG3-window screenshot to the next message. Local Qwen does not accept images. The app detects the BG3 process and window only to place the overlay and perform that explicit capture.

## Runtime topology

```text
                          +----------------------------------+
                          | Native macOS app                 |
                          | SwiftUI + AppKit                 |
                          | AppState + RunStore              |
                          | GuideRepository + RunSafety      |
                          +--------+-----------+-------------+
                                   |           |
                    reads directly |           | reads/writes directly
                                   v           v
                  Resources/Data/guide-bundle.json     Application Support
                                                      state.sqlite3
                                                      imported-builds.json
                                                      OllamaModels/
                                   |
                         explicit provider choice
                          /                       \
                         v                         v
        bundled Ollama v0.30.10              OpenRouter HTTPS API
        127.0.0.1:11435                      Gemini 3 Flash Preview
        qwen3:4b model files                 key from macOS Keychain

        Map action -------------------------> external browser mapUrl
```

The provider choice is explicit and persisted with app settings. The app never silently changes from Local Qwen to OpenRouter or from OpenRouter to Local Qwen. A failed chat request displays the selected provider's error and clearly labelled bundled-guide advice; a failed import returns the error and does not try another provider.

The Ollama executable is part of the app bundle. The `qwen3:4b` model is not: the user downloads it separately from Settings, and Ollama stores it under `~/Library/Application Support/BG3HonorAssistant/OllamaModels`. The app starts Ollama on demand with cloud access disabled and binds it to `127.0.0.1:11435`, separate from Ollama's usual default port.

OpenRouter requests go directly from Swift to `https://openrouter.ai/api/v1/chat/completions` using `google/gemini-3-flash-preview`. The user's API key is a device-only generic-password item in macOS Keychain. It is not stored in SQLite, imported-build JSON, app settings, the app bundle, or a project server.

The Map action currently opens each act's generated `mapUrl` with `NSWorkspace`. There is no bundled browser map or browser/native run-state bridge in the macOS release runtime.

## Build-time topology

Reviewed source files remain under `data`. Python is used before packaging to validate and compile those files, not after the app is released:

```text
data/*.json, data/*.tsv
          |
          v
backend Python loaders and catalog validation
          |
          v
backend/scripts/export-swift-resources.py
          |
          v
Resources/Data/guide-bundle.json
          |----------------------------------|
          v                                  v
scripts/macos/build-app.sh             Windows MSBuild
          |                                  |
          v                                  v
macOS app bundle                       Windows app package
```

`build-app.sh` does not regenerate the guide. Changes to reviewed data or Python loaders must regenerate and commit `guide-bundle.json` before building the app.

## Repository map

| Path | Responsibility |
| --- | --- |
| `mac/BG3Assistant` | App lifecycle, overlay UI, domain state, direct persistence, guide loading, provider calls, import, capture, and OS integration |
| `Resources/Data/guide-bundle.json` | Generated, read-only guide/catalog input shared by the macOS and Windows runtimes |
| `mac/Tests` | Swift tests for the native app |
| `scripts/macos` | App validation, assembly, signing, direct-release packaging, and release helpers |
| `artifacts/macos` | Ignored Swift/Xcode caches, assembled apps, archives, and packages |
| `data` | Reviewed acts, routes, walkthroughs, decisions, timed events, build progression, abilities, equipment, effects, and icons |
| `backend/app` | Existing standalone server and the Python guide/catalog loaders used at build time |
| `backend/scripts/export-swift-resources.py` | Compiles reviewed data into the Swift guide bundle |
| `backend/scripts/build-standalone.sh` | Builds the separate Python server artifact; it is not called by the macOS app build |
| `backend/app/static/map` | Existing web-map source; it is not bundled by the current macOS app build |

Some legacy Swift backend adapter types remain in the source tree and compile into the target, but `AppState` does not use them for startup, guide loading, chat, import, persistence, or maps. They are not evidence of a packaged companion, and `build-app.sh` does not create `Contents/Resources/backend`.

## Native app

The Swift executable is a menu-bar app with no normal `WindowGroup`. `BG3HonorAssistantApp` owns one `AppState`; `OverlayPanelController` presents a keyable floating `NSPanel` over BG3 when requested.

| Area | Core modules | Role |
| --- | --- | --- |
| Lifecycle | `BG3AssistantApp.swift`, `SingleInstanceGuard.swift`, `AppState.swift` | Enforces one instance, restores the active run, detects BG3, loads the guide, and runs the two-second status loop |
| State coordinator | `AppState.swift`, `AppState+*.swift` | Mutates the run, coordinates persistence and provider requests, derives the current goal, and exposes state to views |
| Domain model | `BG3Models.swift` | Codable guide DTOs and the persisted run, roster, progress, act, build, gear, and chat models |
| Guide | `GuideRepository.swift`, generated `guide-bundle.json` | Decodes all act payloads and the item catalog without a network request |
| Pure rules | `RunSafety.swift`, `GearLogic.swift`, `AbilityProgression.swift`, `LoadoutSlot.swift` | Route/readiness rules, gear arbitration, point-buy rules, ability progression, and canonical equipment slots |
| Persistence | `RunStore.swift`, `ImportedBuildStore.swift` | Stores run snapshots/settings in SQLite and reusable AI imports in JSON |
| AI | `AIProvider.swift`, `AssistantAIClient.swift`, `OllamaRuntime.swift`, `CredentialStore.swift` | Owns explicit provider selection, direct requests, local runtime/model setup, and Keychain access |
| Import | `BuildImportService.swift`, `AppState+Party.swift` | Downloads supported public pages, requests structured extraction, validates/normalizes the draft, and persists the imported build |
| OS services | `BG3Detector.swift`, `ScreenCaptureService.swift`, `SpeechInputService.swift`, `PermissionManager.swift`, `LoginItem.swift` | Window detection, explicit one-shot capture, dictation, permissions, and launch at login |
| Presentation | `OverlayPanelController.swift`, `OverlayView.swift`, `*TabView.swift` | Hosts the peek card, planner tabs, settings, onboarding, and chat |

`AppState` is `@MainActor` and is split into extensions by feature. Screen capture is a separate actor. Guide and chat operations retain run/act/generation checks so late results cannot populate a newly selected context.

The user-facing areas are projections of the same `HonorRun`:

| Surface | State and rules it uses |
| --- | --- |
| Now | `CurrentGoal` precedence: targeted gear, focused/recommended walkthrough step, checkpoint, unavailable route, or completion |
| Route | Walkthrough/checkpoint progress, dependency blockers, focus, outcomes, and the resolved archive |
| Party | Full roster, active four, levels, builds, creation/respec recipes, permanent ability sources, and hirelings |
| Loadout | Current-act build picks, manual slot alternatives, deterministic contention, and confirmed ownership |
| Act | Equipment/consequence review and the immutable transition ledger |
| Chat | Selected provider, current run context, recent turns, optional speech, and an OpenRouter-only screenshot attachment |
| Map | The selected act's external `mapUrl` |

## Data and state authority

| Data | Authority | Notes |
| --- | --- | --- |
| Reviewed guide facts | Files under `data` | Source of route order, dependencies, warnings, consequences, builds, and item rows |
| Released guide/catalog | `guide-bundle.json` | Generated snapshot decoded by `GuideRepository`; AI cannot mutate it |
| Active and archived runs | Full `HonorRun` JSON in `state.sqlite3` | Native code is the complete runtime model owner; one row is active at a time |
| Run history | `run_revisions` in `state.sqlite3` | Keeps the latest 20 snapshots per run |
| App settings | `settings` in `state.sqlite3` | Includes overlay/onboarding state and the selected provider, but no provider key |
| Imported builds | `imported-builds.json` | Installation-local reusable `BuildSummary` values merged over bundled builds by ID |
| OpenRouter key | macOS Keychain | Channel-specific service `com.datamaki.BG3HonorAssistant.openrouter.direct` or `.appstore`, account `api-key`, device-only after first unlock |
| Local model | `OllamaModels/` in Application Support | Downloaded separately by the user; the release bundle contains the runtime, not `qwen3:4b` model data |
| Chat transcript and screenshot | `AppState` memory | The screenshot is consumed by the next OpenRouter message; chat lines are not persisted in run snapshots |

The generated catalog path is:

```text
data/build_overview.tsv ----------> builds
data/build_levels.tsv ------------> build_levels
data/build_ability_targets.json --> setup recipes and typed ability sources
data/gear/act{1,2,3}.tsv ---------> items + build equipment
data/item_effects.json -----------> reviewed effects
data/item_icons.json -------------> reviewed icons
                                   |
                                   v
                         guide-bundle.json
```

Build progression is shared across acts and normally covers levels 1-12; transition builds may intentionally cover only part of that range. Equipment rows, map metadata, route records, walkthroughs, and timed events are act-scoped. Each generated act payload contains shared builds plus the act catalog, so Swift filters equipment by act and the selected character level where needed.

Each `data/acts/act{1,2,3}.json` record declares route availability and a public map URL. Acts 1 and 3 have reviewed routes. Act 2 has reviewed equipment but no app-ready route, so normal Act 2 to Act 3 advancement remains locked.

## Core flows

### Startup and guide loading

1. `AppState` loads and normalizes the active `HonorRun` from SQLite.
2. `GuideRepository` decodes `Resources/Data/guide-bundle.json` and returns the selected act payload and item catalog.
3. Imported builds load from `imported-builds.json` and replace bundled builds with the same ID.
4. `RunSafety` derives readiness locally, and the two-second loop refreshes BG3/window status and reloads local run changes.
5. Ollama is not started unless a Local Qwen status check, model download, chat, or import needs it.

### Chat

1. Swift selects nearby or query-relevant walkthrough entries from the generated guide and combines them with player-confirmed run/party state and up to eight recent non-error turns.
2. `AssistantAIClient` calls only the selected provider. Local Qwen uses `qwen3:4b` through Ollama; OpenRouter uses `google/gemini-3-flash-preview` and may include the one-shot JPEG.
3. Both providers are asked for a strict JSON object containing `answer`.
4. Swift rejects malformed output. Provider failures are visible and include deterministic current-guide advice, but do not trigger a request to another provider.

### Build import

1. Swift accepts a public HTTP or HTTPS URL without embedded credentials and rejects obvious localhost, `.local`, loopback, link-local, and private IPv4 literals.
2. `BuildImportSourceLoader` downloads at most 5 MB and extracts bounded text from HTML, plain text, or PDF content.
3. Swift sends the final source URL and at most 60,000 extracted characters directly to the selected provider with a strict schema.
4. The schema requires explicit `pointBuyScores`, `bonusTwo`, and `bonusOne`. `BuildImportDraft.importedBuild` then deterministically requires a non-empty name, distinct bonuses, an exact 27-point base allocation, unique levels in 1-12, and a valid level-12 class total when a level-12 row is present.
5. Final starting scores are always computed from point buy plus the explicit +2/+1. If the supplied final split does not total 12, Swift replaces it only when the level rows deterministically yield an exact level-12 split. Levels are sorted, and gear acts are normalized to 1-3.
6. The resulting `BuildSummary` is saved to `imported-builds.json`, added to every build picker, and assigned to the initiating member only after any required replacement confirmation. Roster membership never changes.

The importer does not prove class, spell, feat, equipment, or complete progression legality. Imported output remains labelled for player verification. There is no hosted authentication or import quota in this flow; any provider usage is governed by the user's selected local model or OpenRouter account.

### Party, equipment, acts, and guide upgrades

Native build assignments stamp `buildAssignedAt` for `GearLogic`: a contested item goes to the earliest valid claimant, then alphabetical build name; a manual recipient override wins while that recipient still claims the item. Manual slot alternatives participate in loadout, target, pickup, and arbitration logic. `equippedByMember` remains a separate player-confirmed ownership ledger.

Advancing an act requires available route coverage plus explicit equipment and consequence review. The app writes an immutable `ActTransitionRecord`, advances the selected act, and reloads the generated act payload. When `GUIDE_VERSION` changes, native archives the active run and starts a clean run while retaining reusable roster identity and still-valid build presets.

## Development and build

Install Python dependencies only for backend tests and guide generation:

```sh
cd backend
uv sync --extra dev
uv run python scripts/export-swift-resources.py
uv run pytest
```

Build, test, and run the native app without starting a server:

```sh
./scripts/macos/validate.sh
./scripts/macos/build-app.sh
open "artifacts/macos/app/BG3 Overlay.app"
```

Assemble the release-style app:

```sh
./scripts/macos/build-app.sh
codesign --verify --deep --strict "artifacts/macos/app/BG3 Overlay.app"
```

`build-app.sh` compiles the Swift executable, copies the committed guide JSON, downloads and SHA-256-verifies the pinned Ollama v0.30.10 archive when needed, bundles that runtime, and signs the result. It neither invokes `backend/scripts/build-standalone.sh` nor packages a backend directory. Release verification is documented in `docs/developers/RELEASE.md`.
