# Tool Calling Failures

Durable tool-use rules only. Per-incident archaeology purged 2026-07-13 (~900 lines of resolved one-offs removed).

## Shell and paths

- Prefer independent parallel commands over `&&` chains when any step can exit non-zero without meaning failure (e.g. `rg` no match).
- Resolve working directory from the live checkout (`.git` root). After renames, never reuse a stale injected path.
- Paths are relative to the command’s working directory—do not prefix `backend/` again from `backend/`, or `mac/` again from `mac/`.
- Use `python3` / `uv run python`, never bare `python`. Backend imports and pytest: from `backend/`, `uv run --with pytest python -m pytest` (or `.venv/bin/python -m pytest` after a healthy venv). Recreate `.venv` after repo rename.
- Do not pipe curl into a Python heredoc on stdin; write JSON to a temp file first.
- Escape carefully: backticks inside double-quoted shell/`rg` patterns trigger command substitution; apostrophes in `Baldur's Gate 3` need double-quoted paths.
- Use `/bin/rm` when the environment intercepts `rm`. Prefer `sips` over `qlmanage` for SVG→PNG in scripts.
- `swift build` / package commands run from `mac/` (or pass `--package-path mac`). Take native-check file lists from README, not memory.
- Isolated checksum (`shasum -a 256`) is the release hash authority—not trailing characters from concatenated logs.

## Process ownership and backends

- Port 8787 + `/health` ≠ correct release. Prove GUI PID, backend PID/parent, packaged flag, and a schema/payload field from the build under test.
- Force-kill / `SIGTERM` on the GUI can orphan the embedded backend. Prefer normal Quit; then retire only the owned packaged listener.
- Never `pgrep -f` on a backend path for cleanup—the probe command line matches itself. Prefer health identity, packaged flag, or the PID listening on the fixed port; exclude developer uvicorn.
- Long executable names may not match `pgrep -x`; use the exact packaged command path.
- Enumerate every running `BG3HonorAssistant` copy before diagnosing “stale backend”—another bundle can own 8787.
- Mutating browser QA needs `runs_dir` isolation; a different port still shares the default ledger.

## Edits and concurrent work

- Read a file with the Read tool before Write/Edit. Re-read immediately before patching when the user or another agent may be co-editing; merge additively.
- Prefer small patches anchored on exact current text. Do not assume expanded JSON formatting, unique test anchors, or yesterday’s class order.
- Do not append to a path from memory—confirm the file still exists (renames silently create bare files).
- If `swift build` races another agent on the shared `.build`, wait for idle or use an isolated scratch path; do not kill user-owned builds.
- When removing an enum/tab case, update every exhaustive switch in the same change set.

## Browser / Computer Use / web

- Use documented browser APIs only (`tabs.list` / `tabs.new`, Playwright under the tab facade, `domSnapshot`). Prefer IIFEs for multi-statement page scripts. Narrow selectors (article vs its child buttons).
- Browser evaluation may lack `fetch` / `localStorage`—assert visible DOM instead.
- Screenshot timeouts on heavy canvases are common; DOM/endpoint assertions still count as verification.
- Computer Use cannot attach to Metal/fullscreen BG3 (`Invalid app` / `noWindowsAvailable` for the game or non-activating overlay). Do not retry forever; verify through the assistant’s own capture/accessibility or manual player steps.
- Re-query accessibility state after any app rebuild, menu dismiss, or interrupted action—element indexes go stale. Import screenshot helpers in the same call that needs them.
- MapGenie: public `curl` with browser User-Agent/Referer/Accept often works; the in-app browser may still block the site—do not invent workarounds when policy forbids them.
- Reddit scripted access is blocked; use bg3.wiki (`action=parse` / wikitext templates) and other maintained sources. EIP and similar may need a desktop User-Agent.
- Query live model catalogs before wiring chat; retired OpenRouter/Gemini slugs return 404.
- Signed-in Chrome automation requires the extension in the selected profile; do not fall back to another browser for authenticated Mod.io without approval.
- Anonymous Google Sheets sessions disable File → Import; stop remote mutation and deliver verified XLSX instead.
- `artifact-tool`: `setActiveWorksheet` takes a sheet name string, not a worksheet object.

## Data and packaging probes

- Inspect JSON schema before counting: `act1_walkthrough.json` is a top-level array keyed by `kind`, not `{steps:…}` / `type`.
- Validate Script Extender JSON with `jq empty` (or similar)—`plutil -lint` can reject valid JSON objects.
- `.pak` tooling: fail closed when `oliver`/Divine is missing; valid package structure ≠ live Script Extender compatibility.
- One-off `uv run --with pytest` environments omit project deps (e.g. OpenCV)—run through the declared backend environment for import-heavy suites.

## 2026-07-13 — Referenced goal file is absent

- Tool: `exec_command` (`cat goal.md`)
- Error: `updated_goal.md` still lists `goal.md` as required reading, but the live checkout has no `goal.md`.
- Recovery: Treated `updated_goal.md` as the active goal, read the remaining design/audit/release/meta files, and did not recreate or overwrite a possibly intentionally removed user-owned file.

## 2026-07-13 — Route test helper needed an explicit Swift return

- Tool: `exec_command` (`swiftc` native model checks)
- Error: Adding a local `typedDependencies` value made `walkthroughStep` a multi-statement function, so its trailing `WalkthroughStep(...)` initializer was no longer an implicit return.
- Recovery: Added the required explicit `return` and reran the same native proof.

## 2026-07-13 — Upcoming-dialogue semantics were overconstrained

- Tool: `exec_command` (native model executable)
- Error: The first dependency patch filtered `nextDialogueStep` to currently eligible dialogue only, breaking the established behavior that previews the next upcoming conversation while the player is still on its preceding exploration step.
- Recovery: Kept typed blockers on the automatic route recommendation and focused-step UI, but preserved upcoming-dialogue preview semantics; the dialogue detail can show its prerequisite blocker without becoming the recommended route step.

## 2026-07-13 — Repeated the package directory in a read path

- Tool: `exec_command` (`sed`)
- Error: Ran from `mac/` but requested `mac/ModelTests/main.swift`, producing `No such file or directory`.
- Recovery: Reused the repository rule that paths are relative to the declared working directory and read `ModelTests/main.swift` directly.

## 2026-07-13 — Used a nonexistent root virtual environment

- Tool: `exec_command` (`.venv/bin/pytest`)
- Error: The repository has no root `.venv`; the documented backend test command uses `uv` from `backend/`.
- Recovery: Kept the JavaScript syntax result, then reran Python checks with the repo-documented `uv run python -m pytest` command from `backend/`.

## 2026-07-13 — Assumed native model checks were a SwiftPM product

- Tool: `exec_command` (`swift run ... BG3AssistantModelTests`)
- Error: `Package.swift` exposes only the app executable; `ModelTests/main.swift` is compiled directly with `swiftc` per the README.
- Recovery: Read the package manifest and used the repository's documented native model-check command.

## 2026-07-13 — Repeated repository prefixes from the backend working directory

- Tool: `exec_command` (`rg backend/...`, `jq data/item_icons.json`)
- Error: The command ran from `backend/` but included repository-root prefixes, so the optional icon-discovery probes reported missing paths.
- Recovery: The build/map data audit in the same command used backend-relative imports and succeeded; subsequent repository-wide reads use the repository root as their working directory.

## 2026-07-13 — Assumed a stale MISTAKES.md section heading

- Tool: `apply_patch` (Monk slot/icon test follow-up)
- Error: The patch targeted a `Build and source truth` heading that had already been consolidated into `Product / data`, so the entire multi-file patch was rejected without changes.
- Recovery: Inspected the live meta file and reapplied the two changes against the existing `Product / data` section and exact TSV row.

## 2026-07-13 — Compact route row exceeded SwiftUI type-check limits

- Tool: `exec_command` (`swift build`, native compact route rail)
- Error: A nested optional `map`/nil-coalescing/interpolation expression inside `Text(...)` could not be type-checked in reasonable time.
- Recovery: Precomputed the detail and status strings before constructing the view, then rebuilt the same UI without changing behavior.
# 2026-07-13 — Swift build issued from repository root

- **Tool:** `exec_command` (`swift build --scratch-path /tmp/bg3-build-chat-context-2`)
- **Error:** `Could not find Package.swift in this directory`; `Package.swift` is under `mac/`.
- **Outcome:** Backend checks in the same fail-fast command passed; the Swift build was rerun from `/Users/jcarbs/Code/bg3_assistant/mac` and the task continued.
# 2026-07-13 — Used the wrong packaged map-data endpoint

- **Tool:** `exec_command` (`curl /api/act1/map` piped to JSON validation)
- **Error:** The route does not exist, so the empty/non-JSON response caused `JSONDecodeError`.
- **Outcome:** `/api/act1/markers` was confirmed from `main.py`, rerun, and packaged marker counts were verified.
# 2026-07-13 — Computer Use resolved a stale bundle identity

- **Tool:** Computer Use `get_app_state` with display name `BG3 Honor Mode Assistant`.
- **Error:** The app catalog resolved the shared display name to retired `com.local.BG3HonorAssistant`, so it reported that the running application was not found.
- **Outcome:** `list_apps` identified the current permanent ID `com.datamaki.BG3HonorAssistant`; subsequent packaged QA targeted that bundle and succeeded.

# 2026-07-13 — Permission build probe mixed repository-relative paths with `mac/`

- **Tool:** `exec_command` (`rg` before `swift build`)
- **Error:** The command ran from `mac/` but searched root paths such as `README.md` and `mac/scripts`, so `rg` failed and the chained build did not start.
- **Outcome:** Recorded the path mistake and reran repository reads from the repository root and Swift commands from `mac/` separately.

# 2026-07-13 — Packaged smoke assumed a standalone builds endpoint

- **Tool:** `exec_command` (`curl /api/act1/builds`)
- **Error:** The packaged API exposes builds inside `/api/act1/route`; the nonexistent endpoint returned HTTP 404 and stopped the fail-fast smoke command.
- **Outcome:** Confirmed the live route declarations in `main.py` and reran the count assertions against `/api/act1/route` plus `/api/act1/markers`.

# 2026-07-13 — Modal consent sheet cancelled AppleScript quit

- **Tool:** `exec_command` (`osascript` quit during package replacement)
- **Error:** The app's open first-run consent sheet returned Apple event error `User canceled (-128)`, leaving the old process and embedded backend alive while the bundle was rebuilt.
- **Outcome:** Used Computer Use only to choose the non-security-changing **Not Now** action, then repeated normal app quit; both processes stopped and port 8787 was released before launching the final package.

# 2026-07-13 — Final verification ignored the documented Python runner

- **Tool:** `exec_command` (`python -m pytest -q`)
- **Error:** Homebrew Python 3.14 does not have pytest installed; the repository documents `uv run --with pytest python -m pytest -q` from `backend/`.
- **Outcome:** Inspected the live README and reran the suite with the repository-owned `uv` environment.

# 2026-07-13 — Final JavaScript probe targeted the retired bundle path

- **Tool:** `exec_command` (`node --check backend/app/static/map.js`)
- **Error:** The map was split into `backend/app/static/map/app.js` and modules under `backend/app/static/map/js/`, so the old single-file path no longer exists.
- **Outcome:** Enumerated the current JavaScript files and syntax-checked every one.

# 2026-07-13 — Packaged marker smoke assumed a bare array

- **Tool:** `exec_command` (`curl /api/act1/markers` count assertion)
- **Error:** The endpoint returns an object containing marker collections, not a top-level array, so iterating the object keys raised `TypeError`.
- **Outcome:** Inspected the live response keys and reran the assertion against the actual packaged payload shape.

# 2026-07-13 — Extracted backend file probe repeated the executable name

- **Tool:** `exec_command` (`file` on extracted packaged backend)
- **Error:** The embedded backend executable is `Contents/Resources/backend/bg3-honor-backend`; the probe incorrectly appended a second `/bg3-honor-backend` path component.
- **Outcome:** Strict app signature, plist identity, and archive hash still passed; the executable architecture probe was rerun against the actual bundle layout.

# 2026-07-13 — TCC database is protected from direct inspection

- **Tool:** `exec_command` (`sqlite3 ~/Library/Application Support/com.apple.TCC/TCC.db`)
- **Error:** macOS returned `authorization denied`; the Codex host does not have Full Disk Access to read the user's TCC database directly.
- **Outcome:** No privacy database state was changed. Diagnosis continued with the signed designated requirement, app/UI state, unified TCC logs, and Apple's public API contract.

# 2026-07-13 — zsh resolved `log` as its arithmetic builtin

- **Tool:** `exec_command` (`log show` TCC diagnostic)
- **Error:** zsh invoked its `log` builtin and returned `too many arguments` instead of running macOS Unified Logging.
- **Outcome:** Reissued the read-only diagnostic with the explicit `/usr/bin/log` path.

# 2026-07-13 — Two-day Unified Log comparison was too broad

- **Tool:** `exec_command` (`/usr/bin/log show --last 2d` for old/new bundle IDs)
- **Error:** The read-only query produced no filtered output after 60 seconds and was interrupted to avoid blocking the goal.
- **Outcome:** The focused 30-minute log already supplied the decisive current TCC attribution, bundle/team identity, prompt state, and denial action; diagnosis continued from that evidence and the committed prior bundle ID.

# 2026-07-13 — Entitlement audit assumed full Xcode was installed

- **Tool:** `exec_command` (`rg`/`find` under `/Applications/Xcode.app/.../MacOSX.sdk`)
- **Error:** This machine has Command Line Tools rather than a full `/Applications/Xcode.app`, so the requested SDK path does not exist.
- **Outcome:** No entitlement was guessed or added. The public capture APIs, current signed entitlements, build environment, and Apple documentation remain the authority.

## 2026-07-13 — Injected checkout path was stale after repository rename

- **Tool:** `exec_command` (memory and Computer Use skill read)
- **Error:** The injected working directory `/Users/jcarbs/Code/civ7-assistant` no longer exists, so process creation failed before the command ran.
- **Outcome:** Re-resolved the live repository as `/Users/jcarbs/Code/bg3_assistant`, reran the read there, and kept subsequent commands rooted at the actual `.git` checkout.

## 2026-07-13 — Multi-file meta patch used an over-specific anchor

- **Tool:** `apply_patch` (failure log plus live-capture LAB entry)
- **Error:** The combined patch failed verification at a heading anchor even though the intended append location was present near EOF; neither file changed.
- **Outcome:** Re-read both file tails and reapplied smaller patches anchored on the exact final lines.

## 2026-07-13 — Computer Use bundle ID was ambiguous

- **Tool:** Computer Use `get_app_state` (`com.datamaki.BG3HonorAssistant`)
- **Error:** Both the installed bundle and repository-built bundle share the permanent identifier, so the automation runtime refused the ambiguous target.
- **Outcome:** Targeted `/Applications/BG3 Honor Mode Assistant.app` explicitly for packaged-app QA.

## 2026-07-13 — Screenshot helper bindings were not initialized after a failed UI read

- **Tool:** Computer Use Node REPL (`fsCU2` / `urlCU2`)
- **Error:** The preceding locked-screen call failed before defining the helper bindings, so the next image-emission attempt raised `fsCU2 is not defined` after successfully retrieving app state.
- **Outcome:** Reused the retrieved state for accessibility evidence and kept later reads text-only unless the image helpers were initialized in the same call.

## 2026-07-13 — Meta-note patch used stale tail context

- **Tool:** `apply_patch`
- **Error:** The combined LEARNINGS/MISTAKES patch expected lines from the wrong file tail and failed verification without changing either file.
- **Outcome:** Read both tails, anchored each addition to its actual final line, and applied the notes successfully.

## 2026-07-13 — Packaged log slice used an unmatched regex

- **Tool:** `exec_command` (`rg` + `sed`)
- **Error:** The server PID was wrapped in regex brackets, so `rg` returned no start line and `sed` received an empty address.
- **Outcome:** Switched to a fixed-string PID match and validated the slice before counting capture endpoints.

## 2026-07-13 — Uvicorn lifecycle and access logs were split

- **Tool:** `exec_command` packaged log counter
- **Error:** The corrected fixed-string start marker was searched in `backend.stdout.log`, but Uvicorn writes lifecycle lines to stderr and access requests to stdout.
- **Outcome:** Counted new access lines from a captured stdout offset instead of trying to join the two append-only streams by line number.

## 2026-07-13 — Equipment-state patch assumed the wrong Swift conformance

- **Tool:** `apply_patch`
- **Error:** The patch anchored on `BuildGear: Codable, Identifiable`, while the current type also conforms to `Hashable`, so verification failed without changing the file.
- **Outcome:** Inspected the authoritative declaration and reapplied the additive model changes against the exact current context.

## 2026-07-13 — Multi-section AppState patch crossed reordered contexts

- **Tool:** `apply_patch`
- **Error:** A single patch spanning published state, chat snapshot, map handoff, roster mutation, and chat capture could not match one mid-file context after earlier edits.
- **Outcome:** Split the change into narrow, independently anchored patches and verified each affected section before compiling.

## 2026-07-13 — Cross-file JavaScript patch used the wrong update header

- **Tool:** `apply_patch`
- **Error:** The patch tried to match `app.js` import lines while still scoped to `state.js`, so verification failed without changing either file.
- **Outcome:** Applied the export, import, and URL-recompute changes as separate file-scoped patches.

## 2026-07-13 — Regression sessions expired across context compaction

- **Tool:** `write_stdin`
- **Error:** Polling the three previously started full-regression sessions returned `Unknown process id` after context compaction, so their final output was unavailable.
- **Outcome:** Restarted the full regression commands from scratch and treated only the fresh results as release evidence.

## 2026-07-13 — Packaged schema smoke assumed fields on the wrong endpoints

- **Tool:** `exec_command` (`curl` route smoke)
- **Error:** The first probe called `/api/route`, and the corrected `/api/act1/route` probe then assumed the route response also contained `markers`; both produced `KeyError` in the parsing command.
- **Outcome:** Read the FastAPI routes and split the smoke check across `/api/act1/route` and `/api/act1/markers`.

## 2026-07-13 — Computer Use roster parser assumed a visible Karlach line

- **Tool:** Computer Use Node REPL
- **Error:** An automatic overlay collapse made the scripted `KARLACH` line lookup return no match, so reading `.match` from the missing status line failed.
- **Outcome:** Re-queried the live accessibility tree, verified the persisted status directly, and kept subsequent UI sequences within one fresh-state action.

## 2026-07-13 — Meta patch included an empty file hunk

- **Tool:** `apply_patch`
- **Error:** A combined code/meta patch contained an empty `MISTAKES.md` update hunk and was rejected without changing any file.
- **Outcome:** Applied the two code edits separately, then added the meta notes with concrete context.

## 2026-07-13 — Overlay auto-collapse invalidated Computer Use element IDs

- **Tool:** Computer Use Node REPL
- **Error:** Several multi-step Party/Loadout QA sequences returned `The user changed ... Re-query the latest state` or an invalid element ID because the hover-owned overlay collapsed between accessibility reads.
- **Outcome:** Broke QA into short fresh-state actions, saved evidence after each stable surface, and used the persisted isolated run plus a final-package restart for the authoritative roster/chat proof.

## 2026-07-13 — Packaged health smoke started before backend readiness

- **Tool:** `exec_command` (`curl /health`)
- **Error:** A fixed three-second delay was insufficient for the newly installed frozen backend, so the first smoke probe exited with curl code 7.
- **Outcome:** Replaced the fixed delay with a bounded readiness poll; the packaged child became healthy with correct GUI parentage.

## 2026-07-13 — In-app browser pointer did not synthesize CSS hover

- **Tool:** Browser `cua.move`
- **Error:** The first move targeted a row partly covered by the sticky panel, and subsequent moves over an unobscured 46-pixel route row never produced a DOM `:hover` match even with the browser visible.
- **Outcome:** Verified the exact shared `.walk-rail-row:hover, :focus-within` style in source, captured the real 46-pixel row and native keyboard-focus state, confirmed zero browser console errors, and recorded the missing pointer capability instead of claiming a synthetic hover screenshot.

## 2026-07-13 — UX audit used a stale fight-data filename

- **Tool:** `exec_command` (Python TSV sample)
- **Error:** The audit tried to open removed `data/act1_fights.tsv`; the repository now stores fight facts in `data/act1_fights.json`.
- **Outcome:** The source inspection and walkthrough sample succeeded; subsequent fight-copy inspection uses the current JSON artifact.

## 2026-07-13 — Recovery cleanup dropped required SwiftUI actor isolation

- **Tool:** `exec_command` (`swift build`)
- **Error:** Removing the now-unused `AppState` parameter also removed `@MainActor` from `incidentProtocolCard`, but the helper still calls the main-actor-isolated `bg3InsetSurface` modifier.
- **Outcome:** Restored `@MainActor`; the follow-up Swift build passed.

## 2026-07-14 — SQLite store used String as a byte sequence

- **Tool:** `exec_command` (`swift build`)
- **Error:** The first SQLite implementation passed `String` directly to `Data.init` and used an ambiguous C-string initializer for SQLite error pointers; Swift requires explicit UTF-8 views and pointer closure types.
- **Outcome:** Converted query strings with `Data(value.utf8)` and mapped SQLite error pointers through an explicit closure; the follow-up build proceeded.

## 2026-07-14 — Targeted backend tests ran outside the backend project

- **Tool:** `exec_command` (`uv run pytest`)
- **Error:** Running from the repository root used the wrong uv environment, so test collection could not import `cv2`.
- **Outcome:** Re-ran the same tests from `backend/`, which selects the project dependencies.

## 2026-07-14 — First unified-state tests exposed two stale-authority merges

- **Tool:** `exec_command` (targeted pytest)
- **Error:** A party-only update preferred the previously expanded default roster, changing Shadowheart's supplied id, and chat treated older backend equipment as authoritative even when the native snapshot explicitly said ownership was unknown.
- **Outcome:** Party-only API updates now normalize the supplied party, and chat trusts the request's explicit ownership state instead of reviving stale backend data.
## 2026-07-14 — Computer Use app targeting required a fresh binding

- **Tool:** `mcp__node_repl__js` / `sky.get_app_state`
- **Error:** `com.datamaki.BG3HonorAssistant` matched both the installed app and the isolated repository build. Later retries referenced bindings (`qaState`, `isolatedPartyAfterRestart`, and `fsQa`) whose declarations never completed because an earlier call threw.
- **Resolution:** Retried with the full path to the isolated packaged app and a fresh `var` binding, as required by the Computer Use workflow.
- **Outcome:** Persistence QA continued against the intended isolated package.

## 2026-07-14 — Combined mod-defer patch used stale checklist context

- **Tool:** `apply_patch`
- **Error:** The release checklist contained an additional telemetry line, so the large multi-file patch could not match its expected block.
- **Resolution:** Re-read the current sections and split the change into small exact patches.
- **Outcome:** The mod was still removed from the default validation scope without touching its deferred source.

## 2026-07-14 — Backtick in a double-quoted `rg` pattern broke shell parsing

- **Tool:** `exec_command`
- **Error:** A final documentation search included a Markdown backtick inside a double-quoted shell pattern, producing `zsh: unmatched \"`.
- **Resolution:** Retried with a single-quoted pattern that omitted the Markdown delimiter.
- **Outcome:** The final mod-validation reference audit completed successfully.
