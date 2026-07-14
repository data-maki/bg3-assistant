# Learnings

Durable product and environment facts only. Incident archaeology purged 2026-07-13; if a rule is still true, it lives here once.

## Product invariants

- Honor Mode assistance is a deterministic route/checkpoint engine. Vision and chat identify context and explain; they must not invent the route or silently advance irreversible steps.
- Collapsed pet shows one verdict and one blocker; expanded planner is reference depth. Prefer phase-specific relevance over persistent information density.
- Competitive-overlay lesson: highlight decisions and offer choices; do not remove or dictate the decision.
- Honor Mode guidance must pass a strict value test: encounter-specific, non-obvious, consequential, and actionable. Routine healing, resting, initiative cleanup, ordinary hazard avoidance, and generic looting caution are assumed player competence and should not occupy the overlay.
- Dialogue, evidence gates, fights, and pickups share one progression contract: prerequisites, minimum level, player-confirmed completion, explicit consequences, compact incident protocol. Dialogue is route state, not background notes.
- Route order, level safety, and story eligibility are separate. Recommend only steps whose evidence and branch prerequisites are satisfied; a focused blocked step must name the blocker.
- `PICKUP`/`EXPLORE` stay pickup/explore. Only dialogue/decision steps and fight-opening conversations render as `TALK`.
- Party level drives an activity ladder: safe XP, next core challenge, level gate, and first-class dialogue outcomes—not one fight card.
- Level-aware recommendations stay inside contiguous travel phases (Nautiloid/surface → Underdark → Grymforge → Crèche); do not bounce a higher-level party back out of region.
- Separate map identity (`Wilderness`, `Underdark`, …) from semantic region so markers never land on the wrong raster.
- Survival planner is task-first: party level, builds, completion, and travel phase generate a small pursuit list; category filters are secondary.
- Level-up execution and equipment acquisition are different jobs: current-level choices in Party; act-scoped gear/location in Equipment; preserve member identity so a four-build party is never anonymous build IDs.
- Honor-run party state is a full persistent roster plus an active-party projection capped at four. Readiness uses only active members; camp/dead/departed/unrecruited keep builds and loadouts.
- A selected reviewed build is assumed setup at that level (choices, tactics, listed gear). Free-form capability tags are only for deviations.
- Every selectable build needs a tested current-act interim loadout even when defining items arrive later. Endgame or post-respec pieces never stand in for Act 1 slots.
- Keep app-ready builds, Act-1-only reviewed builds, and source-only research in separate statuses; only the first two belong in the player picker.
- Build selectors contain only playable character plans. Item packages (e.g. Shadow Blade) and known non-Honor progressions (e.g. Lockadin) stay out.
- Keep each referenced build as its own versioned plan; similar names must not be blended.
- Expose all reviewed gear to party/equipment UI; keep `/api/act1/markers` explicitly Act 1-only.
- MapGenie is a live reference and handoff, not an asset to clone. Own a local auditable marker dataset.
- Local ORB/RANSAC artwork registration is authoritative for marker projection; region bounds are interior/offline fallback only.
- Two-second screenshot loop uses a cheap local map-open detector; LLM vision stays on-demand.
- Grounded chat needs a deterministic context snapshot: route eligibility, focus, active roster, inactive outcomes, current build steps, relevant equipment, authority labels—not just checkpoint ID plus four party rows.
- Decision guidance states recommended choice, what it preserves, what it sacrifices, and reversibility.
- The vanilla ScreenCaptureKit/manual route is the product baseline. Optional telemetry is still a mod: disclose install, achievements, save metadata, patch compatibility, and trust independently.
- Structured telemetry can update transient context; encounter completion stays player-confirmed.
- Official Mod.io publication is Toolkit-originated and PC-only. Script Extender JSON file transport is third-party unless redesigned. Valid `.pak` ≠ Script Extender compatibility with the current patch.
- Computer Use / external operators must not be silently embedded. Native app stays input-free: export a deterministic queue, let an explicit operator place pins, then require screenshot evidence plus manual confirmation.
- BG3-native custom markers are the durable navigation layer; local screenshot alignment is one-shot transform/placement verification.

## Overlay / capture / packaging

- Separate material behavior from visual identity: native Liquid Glass underneath restrained BG3 cues (umber, bronze/gold, parchment, serif, tooltip geometry)—no copied assets.
- One adaptive outer glass surface; separators for rows; tinted fills only for safety-critical state. Collapsed form is a low horizontal middle-right tooltip (~304×128), not a tall pet card.
- Party setup optimizes four parallel decisions (companion, level, build, NOW→NEXT), not four editable character documents.
- Overlay position: read normalized anchor before layout changes; never persist programmatic resize/reference frames; compare resulting frame to programmatic target to detect user drags; migrate behavior-changing defaults once.
- Pet atlas: pause on neutral outside hover; preserve authored hover durations; map pointer angle into look rows; keep sprite interaction outside drag-handle overlays.
- Overlay visibility is process ownership: per-user OS lock before SwiftUI starts; activate owner on contention; retire legacy copies before panel/backend creation.
- Control-window and menu-bar scenes can enter the same async startup concurrently. A synchronous `isStarting` latch is required in addition to the cross-process lock.
- Detect BG3 via `com.larian.bg3` / explicit Baldur’s Gate names—never a generic `bg3` substring that matches the assistant.
- Capture the largest matching visible Larian window (auxiliary thin strips exist); capture 1:1 at reported pixel size—do not force 2×.
- Enumerate off-screen/other-Space windows. `CGPreflightScreenCaptureAccess` is only a raw TCC hint; missing/minimized BG3 is capture health, not “permission denied.” Include `NSScreenCaptureUsageDescription`, offer a first-launch consent sheet when the hint is missing, and invoke the TCC request synchronously from its Continue button. Background refreshes never prompt, and successful pixel capture is authoritative.
- Borderless `NSPanel` needs `canBecomeKey` overridden or overlay text fields never receive keyboard focus.
- Distributable shell embeds FastAPI + guide/static assets; repo/`uv` are dev fallbacks. Frozen state and secrets live in Application Support (`…/BG3HonorAssistant/backend/.env`), never in the signed bundle.
- Backend lifecycle needs executable path and parent PID. Port 8787 and `/health` alone are insufficient: orphaned packaged backends can serve stale payloads. Startup retires matching packaged backends before health; release verification also checks a new schema field or embedded content hash. Quit via normal app lifecycle for smoke tests.
- `Settings.runs_dir` is shared across ports; mutating browser QA needs an isolated runs directory.
- Apple Development signing ≠ Developer ID / notarization for public distribution. This machine currently lacks a Developer ID Application identity.
- Rebuild-in-place does not update a running process; verify UI after explicit restart with new GUI PID owning the backend.
- The first working local build used `com.local.BG3HonorAssistant`; the release uses `com.datamaki.BG3HonorAssistant`. TCC grants do not migrate across that identity change, so one new approval is required. Run that approval from `/Applications`, then keep the bundle ID, signing certificate, and installed path stable.

## Environment / verification

- Shell has `python3` / `uv run python`, not `python`. Portable tests: from `backend/`, `uv run --with pytest python -m pytest`. Prefer `uv run python` over system Python for backend imports.
- After repository rename, recreate `.venv`—shebangs may still point at the old checkout path.
- Native checks: Command Line Tools SDK has neither XCTest nor Swift Testing; compile production sources with `ModelTests/main.swift` per README; `swift build` from `mac/`.
- BG3 install: `~/Library/Application Support/Steam/steamapps/common/Baldurs Gate 3/Baldur's Gate 3.app`; Steam app ID 1086940.
- Apache-2.0 `oliver` is the macOS `.pak` build fallback; packaging and live event delivery are separate gates.
- Spreadsheet/workbook work: prefer verified local XLSX when the visible Sheet is an anonymous read-only session; `artifact-tool` wants a sheet name string in `setActiveWorksheet`; prefer explicit `SEARCH`/`ISNUMBER` over wildcard `COUNTIF` in that renderer; never paste cells starting with `=+/ -@` unless intentional formulas. Import guide data by stable sheet title, not numeric `gid`.
- GitHub SSH push and `gh`/app API authorization are independent; refresh CLI repo scope when SSH works but API returns 404.
- Long-running goals must be rewritten as evidence changes: proved baseline, must-not-regress, smallest remaining acceptance gaps—never treat a stale build brief as permission to start over.
- Do not claim remote Sheet updates, live map acceptance, or publishability without observable evidence from the packaged/live surface under test.
- Automatic capture is a user-owned capability, not a baseline requirement. Default it off, share one serialized 30-second frame across enabled consumers, and keep vision evidence separate from player-confirmed route state.
- `BG3_ASSISTANT_STATE_DIR` must derive the embedded backend's `RUNS_DIR`; isolating only `RunStore` leaves localhost QA able to touch the player's backend ledger.
- LaunchServices does not inherit environment variables from a one-off shell process. For Computer Use QA, set the isolated state root with `launchctl setenv` before launching, then unset it during cleanup.
# ScreenCaptureKit enumeration is not a permission probe

On macOS 26, `SCShareableContent.excludingDesktopWindows` can return displays even when the signed app is absent from Privacy & Security → Screen & System Audio Recording. Apple documents `NSScreenCaptureUsageDescription` for ScreenCaptureKit. The tested automatic request did not create a manageable row, while later ScreenCaptureKit attempts were denied without prompting; an explicit consent sheet makes the request observable and user-initiated. An actual screenshot verifies the grant, and a stable bundle ID/code-sign identity keeps that row mapped to the shipping app.
## 2026-07-14 — Keep deferred experiments out of the core release loop

- The telemetry mod is future work, so its simulator, feed contract, package validation, and publication blockers must not run or appear as gates during vanilla overlay iterations.
- Retaining experimental source does not imply retaining its tests in the default product suite; reintroduce them only with a separate mod milestone.
