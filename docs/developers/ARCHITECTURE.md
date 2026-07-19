# Architecture

BG3 Honor Mode Assistant is a menu-bar macOS app with a native in-game overlay, a packaged localhost companion, an optional hosted AI service, and an Act 1 browser map. Guide and run features need no project-hosted service. Hosted releases route configured AI chat and public-URL build imports through one; development can call providers from the local companion instead. The browser map still downloads MapGenie tiles, and later-act map handoffs open public sites.

## Product boundary

The app shows the current risk, recommended action, route progress, party and build guidance, equipment plans, act-transition checks, and guide-grounded chat. Progress, outcomes, party status, and equipment ownership change only when the player confirms them.

It is not a BG3 mod. It does not read game memory or saves, edit game files, automate input, infer progress, take periodic screenshots, or record gameplay. With permission, chat may attach one player-visible BG3-window screenshot to the next message. The app can detect the BG3 process and window only to place the overlay and perform that explicit capture.

## System topology

```text
                           verified AppTransaction JWS
                                      |
                                      v
+----------------------+      +----------------------+       +----------------------+
| Native macOS app     | HTTP | Local companion      | HTTPS | Hosted backend       |
| SwiftUI + AppKit     +----->| FastAPI, loopback    +------>| FastAPI, /v1/* only  |
|                      |      |                      |       |                      |
| AppState             |      | guide/catalog APIs   |       | Apple verification   |
| RunStore             |      | map + state bridge   |       | auth + import quota  |
| overlay and services |      | AI proxy             |       | OpenRouter + Exa     |
+----------+-----------+      +----+-------------+---+       +----------------------+
           |                       |             |
           | direct SQLite         | SQLite      | serves local assets/API
           v                       v             v
     state.sqlite3 <---------------+       Act 1 browser map ----> MapGenie tiles
       | runs and revisions                       |
       | settings                                 +--> localStorage fallback
       | builds and items
       +--> installation-local imported builds

Bundled data/*.json and data/*.tsv ---> local companion guide loaders/catalog seed
                                  `---> hosted guide grounding/catalog seed
```

The native app always calls its managed companion at `127.0.0.1:8787`; it never calls the hosted service directly. A configured remote URL is an upstream used by the companion. The browser receives neither hosted credentials nor the companion control token.

The same Python application runs in two mutually exclusive modes:

| Mode | Exposed surface | Persistence role |
| --- | --- | --- |
| `local` | `/health`, local guide/catalog APIs, browser map, run-state bridge, `/api/chat`, `/api/builds/import`, and `/_companion/session` | Shares the app's run/catalog SQLite database and persists imported builds locally |
| `hosted` | `/health` and authenticated `/v1/*` routes only | Verifies Apple transactions, holds provider credentials, seeds its own catalog for chat grounding, and keeps a separate build-import usage ledger; it does not persist user imports |

`backend/app/main.py` enforces this split by returning 404 for routes that do not belong to the active mode.

## Repository map

| Path | Responsibility |
| --- | --- |
| `mac/BG3Assistant` | App lifecycle, overlay UI, domain state, local persistence, companion process ownership, chat/capture, and StoreKit authentication |
| `backend/app` | FastAPI composition, guide parsing, relational catalog, browser/native state bridge, AI grounding, build import, auth, and quota |
| `backend/app/static/map` | Act 1 Leaflet map, walkthrough and party panels, and browser-side state projection |
| `data` | Reviewed act contracts, routes, walkthroughs, decisions, timed events, build progression, abilities, equipment, effects, and icons |
| `backend/scripts` | Standalone companion build and data-maintenance scripts |
| `mac/scripts` | App assembly, signing, direct-release, and TestFlight packaging |

## Native app

The Swift executable is a menu-bar app with no normal `WindowGroup`. `BG3HonorAssistantApp` owns one `AppState`; `OverlayPanelController` presents a keyable floating `NSPanel` over BG3 when requested.

| Area | Core modules | Role |
| --- | --- | --- |
| Lifecycle | `BG3AssistantApp.swift`, `SingleInstanceGuard.swift`, `AppState.swift` | Enforces one instance, owns startup/shutdown, restores the active run, checks backend health, detects BG3, loads guide data, and runs the two-second synchronization loop |
| State coordinator | `AppState.swift`, `AppState+*.swift` | Mutates the run, coordinates persistence and network requests, derives the current goal, and exposes feature state to views |
| Domain model | `BG3Models.swift` | API DTOs and the persisted `HonorRun`, roster, progress, act, build, gear, chat, and auth models |
| Pure rules | `RunSafety.swift`, `GearLogic.swift`, `AbilityProgression.swift`, `LoadoutSlot.swift` | Route/readiness rules, gear arbitration, ability validation, and canonical equipment slots |
| Persistence | `RunStore.swift` | Reads and writes full run snapshots, revisions, and app settings directly in SQLite |
| Companion boundary | `BackendProcessManager.swift`, `BackendEndpoint.swift`, `BackendClient.swift` | Starts and retires the loopback process, validates upstream configuration, and owns all native HTTP calls |
| OS services | `BG3Detector.swift`, `ScreenCaptureService.swift`, `SpeechInputService.swift`, `PermissionManager.swift`, `LoginItem.swift` | Window detection, explicit one-shot capture, dictation, permissions, and launch-at-login |
| Presentation | `OverlayPanelController.swift`, `OverlayView.swift`, `*TabView.swift` | Hosts the peek card, planner tabs, settings, onboarding, and contextual chat |

`AppState` is `@MainActor` and is split into extensions by feature: persistence, party, acts, route, gear targets, chat, capture, onboarding, overlay, and current-goal selection. Screen capture is a separate actor. Guide and chat requests carry generation and run/act checks so a late response cannot populate a newly selected context.

The user-facing areas are projections of the same `HonorRun`:

| Surface | State and rules it uses |
| --- | --- |
| Now | `CurrentGoal` precedence: targeted gear, focused/recommended walkthrough step, checkpoint, unavailable route, or completion |
| Route | Walkthrough/checkpoint progress, dependency blockers, focus, outcomes, and the resolved archive |
| Party | Full roster, active four, levels, builds, creation/respec recipes, permanent ability sources, and hirelings |
| Loadout | Current-act build picks, manual slot alternatives, deterministic contention, and confirmed ownership |
| Act | Equipment/consequence review and the immutable transition ledger |
| Chat | Current run context, recent turns, optional speech, and one removable screenshot attachment |
| Map | Local Act 1 map or the configured public map handoff for later acts |

## Local companion and hosted backend

`backend/app/main.py` composes the API. Supporting modules keep the major responsibilities separate:

| Modules | Responsibility |
| --- | --- |
| `config.py`, `paths.py` | Environment settings and checkout-versus-PyInstaller resource paths |
| `models.py` | Pydantic request/response contracts shared by route handlers |
| `route_data.py`, `walkthrough_data.py` | Parse and validate reviewed act, route, build, ability, equipment, and dependency data |
| `catalog.py` | Seed and query relational builds/items; persist imported builds and enrich unknown items |
| `stores.py` | Merge the browser's limited state projection into full native run snapshots; store manual map position |
| `map_data.py` | Build Act 1 marker payloads and map MapGenie coordinates, anchors, regions, and tile metadata |
| `chat_context.py`, `llm_chat.py`, `guide_chat.py`, `web_search.py` | Resolve trusted guide context, call OpenRouter/Exa when configured, reconcile citations, and provide deterministic fallback answers |
| `loadout_import.py` | Preflight and fetch a public URL, extract bounded page text, request structured build output, and derive a legal 27-point creation recipe |
| `auth.py`, `usage.py` | Verify AppTransaction JWS values, issue scoped bearer tokens, and enforce idempotent import quota reservations |

The important local routes are:

| Route | Consumer and purpose |
| --- | --- |
| `GET /api/acts/{act}/guide` | Native guide load: selected-act route/walkthrough/events, shared builds, and all-act metadata |
| `GET /api/items` | Native loadout slot picker |
| `GET /api/act1/markers` | Browser map guide, pickup, build, region, and tile payload |
| `GET/POST /api/run-state` | Browser projection of the active native run |
| `GET/POST /api/position` | Best-effort manually selected map position; this is not game telemetry |
| `POST /api/chat` | Deterministic or proxied AI chat; companion-token protected when a hosted upstream is configured |
| `POST /api/builds/import` | Import proxy and local catalog persistence; companion-token protected when a hosted upstream is configured |
| `PUT /_companion/session` | Always-control-token-protected AppTransaction-to-hosted-session exchange |

## Data and state authority

| Data | Authority | Notes |
| --- | --- | --- |
| Reviewed guide facts | Files under `data` | AI cannot alter reviewed route order, dependencies, warnings, consequences, builds, or item rows |
| Build/item catalog | `items`, `builds`, `build_levels`, and `build_items` in local `state.sqlite3` | Reviewed exports seed once per `GUIDE_VERSION`; imported builds survive reseeds, and unknown imported items may begin as unreviewed model output |
| Active and archived runs | Full `HonorRun` JSON in the SQLite `runs` table | Native code is the complete model owner; one row is active at a time |
| Run history | `run_revisions` | Keeps the latest 20 snapshots per run |
| App settings | SQLite `settings` | Includes native settings and the catalog seed version; overlay position itself is in `UserDefaults` |
| Browser run state | Projection merged through `/api/run-state` | The browser cannot edit native-only fields such as act reviews, slot overrides, gear arbitration, or preparation checklists |
| Browser fallback/UI state | Browser `localStorage` | Can seed an empty server projection; timed-event acknowledgements remain browser-only |
| Manual map position | `position.json` | Set by right-click on the browser map and polled by the map; no native producer currently exists |
| Hosted grounding catalog | Hosted `state.sqlite3` | Separately seeds reviewed builds/items for chat; it does not contain installation-local imports |
| Hosted import usage | Separate hosted `usage.sqlite3` | Never shares the installation-local run/catalog database |
| Hosted bearer | Companion process memory | Never persisted or exposed to browser JavaScript |

The catalog seed path is:

```text
data/build_overview.tsv ---------> builds
data/build_levels.tsv -----------> build_levels
data/build_ability_targets.json --> validated build recipes and typed ability sources
data/gear/act{1,2,3}.tsv --------> items + build_items
data/item_effects.json -----------> reviewed effects
data/item_icons.json -------------> reviewed icons
```

Build progression is shared across acts and normally covers levels 1-12; transition builds may intentionally cover only part of that range. Equipment rows, coordinates, map metadata, route records, walkthroughs, and timed events are act-scoped. API payloads may contain shared builds and items from several acts, so native and browser consumers filter by `act` and the selected act.

Each `data/acts/act{1,2,3}.json` declares route and map availability. Acts 1 and 3 have reviewed routes. Act 1 has the local browser map; Acts 2 and 3 hand off to public maps. Act 2 has reviewed equipment but no app-ready route, so normal Act 2 to Act 3 advancement remains locked.

## Core flows

### Startup and guide loading

1. `AppState` loads and normalizes the active `HonorRun`, creates an ephemeral companion control token, and prepares the fixed localhost client.
2. `BackendProcessManager` checks the identity of a responding service on port 8787, retires an unowned stale companion when safe, and starts the bundled executable or a development Uvicorn process.
3. The child receives `BG3_BACKEND_MODE=local`, the shared SQLite path, the control token, and either a remote upstream URL or development-only provider settings.
4. Native loads the selected act's guide and item catalog, computes readiness locally with `RunSafety`, and starts polling health and the shared run snapshot.

`BG3_BACKEND_URL` can come from the runtime process environment. Packaging also reads it from the build environment or repository-root `.env` and writes it as `BG3BackendURL` in `Info.plist`. A non-local value must be a pathless HTTPS origin and is passed to the companion as `BG3_UPSTREAM_BACKEND_URL`.

### Progress and browser synchronization

Native writes complete run snapshots directly through `RunStore`. The Act 1 map reads a smaller projection at startup, caches edits in `localStorage`, and posts them after a short debounce. `stores.py` preserves unknown properties when it merges members with matching IDs, but incoming known fields and roster membership win.

Native polls SQLite every two seconds and immediately before its own writes. If it observes a map change first, it adopts that snapshot and cancels the stale native save. This is lightweight synchronization, not an atomic compare-and-swap. The browser neither reloads run state continuously nor sends a run/act identity, so an old tab can post stale known fields or roster membership into whichever run is active after a run or act switch.

Route/readiness behavior exists in three runtimes: Swift `RunSafety` drives native UI, Python guide logic grounds chat, and browser JavaScript drives map recommendations. They consume the same IDs and dependencies but are not one shared implementation. One known difference is that native treats `caughtUp` as completed, the map bridge translates it to `done`, and Python chat logic does not currently recognize it. Rule changes need parity checks across all three.

### Chat and authentication

Native sends current run context, the selected guide activity, up to eight recent turns, and an optional JPEG to local `/api/chat`. The backend re-resolves guide IDs rather than trusting prose supplied by the client. Without configured AI it returns deterministic guide answers; with AI it calls OpenRouter and can use Exa for uncovered questions.

For a hosted release, native obtains `AppTransaction.shared` from StoreKit and sends the verified JWS only to controlled local `/_companion/session`. Hosted `/v1/auth/app-transaction` verifies it against pinned Apple roots, pseudonymizes `appTransactionId`, and returns a scoped bearer with a configurable lifetime of one hour by default. The companion keeps that bearer in memory and injects it into chat/import requests.

The hosted service re-resolves context against its own bundled guide and catalog. Companion and hosted deployments therefore need compatible guide IDs; there is no protocol negotiation, and installation-local imported build details are not available to hosted chat grounding.

### Build import

1. A member-specific Party action posts a public URL and stable UUID idempotency key to local `/api/builds/import`.
2. The companion authenticates upstream and calls hosted `/v1/builds/import` with `persist=false`.
3. Hosted quota admission uses `BEGIN IMMEDIATE`, charges each unique attempt once, and uses leased execution IDs so retries cannot double-charge or let a late worker overwrite a newer result.
4. The importer rejects URLs whose preflight resolution is non-public, bounds and extracts supported content, and sends the source URL plus extracted public-page text to the configured structured-output model. DNS is not pinned between preflight and download, so hosted deployment still requires egress controls.
5. Hosted returns a schema-checked build with a legal creation point buy and advisory labels that call for player review. It does not prove class, spell, feat, gear, or full progression legality.
6. Only the local companion inserts the build, levels, item joins, and unknown item rows into the installation's catalog. Unknown item facts originate with the model and receive only best-effort bg3.wiki enrichment.
7. The member-specific flow assigns the result after any required replacement confirmation; the review labels do not enforce another gate. Roster membership never changes.

Release quota is 30 lifetime import attempts per pseudonymous Apple subject. Sandbox and production must use separate origins, signing secrets, and usage databases as an operational deployment requirement.

### Party, equipment, acts, and guide upgrades

Native build assignments stamp `buildAssignedAt` for `GearLogic`: a contested item goes to the earliest valid claimant, then alphabetical build name; a manual recipient override wins while that recipient still claims the item. The map can change a build ID but cannot update assignment timestamps or native override metadata, so a map-side build change may retain stale arbitration state. Manual slot alternatives participate in native loadout, target, pickup, and arbitration logic, but the map does not receive the complete `plannedSlotOverrides` model. `equippedByMember` remains a separate player-confirmed ownership ledger.

Advancing an act requires available route coverage plus explicit equipment and consequence review. The app writes an immutable `ActTransitionRecord`, advances the selected act, and reloads act-scoped guide state. When `GUIDE_VERSION` changes, native archives the active run and starts a clean run while retaining reusable roster identity and still-valid build presets.

## Build and verification

`backend/scripts/build-standalone.sh` creates a PyInstaller companion containing `data` and the browser map. `mac/scripts/build-app.sh` builds the Swift executable, embeds that companion, writes the upstream plist setting, rejects the release OpenRouter key and bundled `.env` files, and signs the app. `build-release.sh` and `build-testflight.sh` add their distribution-specific signing, provider-key checks, and packaging.

CI runs `swift build`, `swift test`, and backend `pytest`. Release verification, including packaging, signing, lifecycle, hosted auth, map behavior, and secret checks, is documented in `docs/developers/RELEASE.md`.
