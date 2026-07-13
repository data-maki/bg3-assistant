# Mistakes

## 2026-07-13

- The web map combined current-level build actions and every recommended item inside one Loadout tab, and reduced the native four-person party to an anonymous set of build IDs.
  - Impact: Players had to scan equipment while leveling and could not tell which character an item belonged to or track shared recommendations separately.
  - Fix: Preserve member ID/name/level/build in shared map state; show only current-level actions in Party; move act-scoped gear into Equipment and track assignment per character.

- The first marker-export regression used `fight-nautiloid-helm`, which is an item-area phrase rather than the canonical route checkpoint ID `fight-nautiloid-zhalk`.
  - Impact: The test incorrectly expected Wilderness markers while the deterministic route correctly remained in the unresolved Nautiloid phase.
  - Fix: Build marker-sync fixtures from canonical route IDs and keep item acquisition names separate from fight progress identifiers.

- The middle-right positioning work optimized the default/reset behavior without proving that a deliberate user drag survives later overlay synchronization and relaunch.
  - Impact: The assistant returns to its default even when the player moved it to avoid game UI or match personal preference.
  - Fix: Treat middle-right as first-run/migration fallback only, persist an explicit user-position flag with the normalized anchor, and regression-test drag persistence across collapse/expand, window updates, and controller recreation.

- Expanding `openActOneMap` with optional build/item/level parameters broke an existing direct `Button(action:)` method reference.
  - Impact: The first Swift verification pass failed before UI validation.
  - Fix: Preserve the zero-argument call through an explicit closure at the control-window call site and include all direct method references in signature-change searches.
- I stopped the running app with `SIGTERM` before packaging, bypassing its normal backend cleanup and leaving the old embedded backend on port 8787.
  - Impact: The first packaged-app smoke launch connected to stale backend code instead of proving the rebuilt bundle.
  - Fix: Quit the app through its normal application lifecycle for release tests, explicitly verify the owned backend PID changes, and remove only the already-orphaned process before relaunching.

- The Party tab treated an approved build as something the player still needed to study: it emphasized the next level and hid actionable equipment behind a broad `Build notes, full levels, and Act 1 gear` disclosure.
  - Impact: At the actual level-up, the player saw information they explicitly did not need while current-act gear, acquisition locations, and map handoff were buried.
  - Fix: Make act a party-wide input, show only the current-level choice and act-relevant equipment/location actions by default, remove next-level and background exposition from the primary flow, and reserve Acts 2/3 as explicit unpopulated data scopes until reviewed.
- The overlay treated the pet atlas as a generic looping GIF and continuously advanced a readiness-selected row.
  - Impact: The pet moved without player interaction, felt distracting over BG3, and discarded the v2 atlas's 16 pointer-look directions that make the Codex pet feel responsive rather than decorative.
  - Fix: Make rest visually still, drive v2 look cells only from hover/pointer position, and keep route danger in the tooltip rather than changing the pet's autonomous animation state.

## 2026-07-12

- Release verification repeatedly launched app copies with `open -na` from repository and extracted ZIP paths, but the product had no process-level ownership guard.
  - Impact: Separate processes each created their own overlay controller, so an expanded planner from one copy and a collapsed pet from another appeared simultaneously over BG3.
  - Fix: Acquire a per-user OS file lock before SwiftUI starts, activate the existing owner when lock acquisition fails, and retire legacy duplicate assistant processes when the new owner starts.
- Overlay move persistence accepted `leftMouseDown` and `leftMouseUp` in addition to real drag events.
  - Impact: Clicking Details or Close while the panel resized could persist the programmatic expanded/collapsed origin as a user placement; the final middle-right anchor drifted from `y=0.5` to `y=0.278`.
  - Fix: Persist position only while AppKit reports `leftMouseDragged`, and migrate the placement schema so existing affected anchors reset once.
- The first Liquid Glass correction solved spacing but treated macOS material as the complete visual identity.
  - Impact: Over BG3, the cool gray panel, standard segmented chrome, indigo accents, and portrait-shaped collapsed card still looked like a separate utility rather than a companion to the game's bronze-framed tooltips and controls.
  - Fix: Preserve native material behavior underneath a restrained BG3-derived theme, use warm bronze/gold hierarchy and parchment text, replace the foreign segmented strip, and make the collapsed state a low horizontal tooltip docked at middle-right.
- The expanded planner used a large fixed frame, allowed its draggable header to accept flexible vertical space, and built hierarchy from many nested opaque rounded rectangles.
  - Impact: The supplied packaged screenshot devoted roughly half the upper panel to empty material, pushed the actual controls down, and looked like an older custom dashboard instead of a current macOS companion.
  - Fix: Constrain chrome to intrinsic height, shrink the planner envelope, use a single availability-gated native Liquid Glass surface, rely on standard controls, and reserve tinted content backgrounds for safety-critical semantics.
- Party setup was technically complete but modeled all four slots as generic editable records with free-form class and capability fields visible by default.
  - Impact: Players had to type story-companion names, interpret internal build data, and scan dense cards before answering the basic setup questions: who is in the party, what level are they, and which reviewed build are they using. During first panel creation, a transient zero-origin SwiftUI resize could be persisted as the anchor; later, resize-time persistence overwrote the centered anchor when BG3's real frame replaced the fallback screen frame.
  - Fix: Make the party structure explicit as one custom character plus three story companions, promote level/build selection, hide deviations behind disclosure, read the normalized anchor once before layout changes, never persist programmatic resize frames, reapply the anchor against the final reference, clamp it, and version the schema so the true middle-right default applies once.
- A responsive pet iteration replaced the required `AVOID` line with Map/Scan launcher buttons and wrapped the entire card in one accessibility label.
  - Impact: The card violated the experienced-player interaction contract, hid individual actions from assistive inspection, and left a large empty draggable tail after the launcher buttons were removed.
  - Fix: Restore exactly Details/Ask/Done plus one concise `AVOID`, expose child accessibility labels, remove the flexible empty drag zone, and verify both the packaged pixels and accessibility tree before release.
- `goal.md` remained an initial greenfield build brief after the Act 1 product was largely implemented and packaged.
  - Impact: A future goal run could waste time rebuilding verified systems instead of closing live-map and public-release gates.
  - Fix: Replaced it with a status-aware shipping goal that names the verified baseline, decision-first UX contract, remaining evidence, external signing inputs, and regression boundaries.
- Screen Recording authorization was incorrectly coupled to a manual per-launch `Test Capture` flag, and ScreenCaptureKit enumerated only the assistant's current macOS Space.
  - Impact: macOS correctly reported the app as authorized, but the two-second loop stayed disabled; BG3 in another/fullscreen Space could also appear absent despite valid permission.
  - Fix: Refresh authorization from `CGPreflightScreenCaptureAccess`, start capture verification automatically, keep capture health as a separate status, and enumerate BG3 windows across Spaces.
- ScreenCaptureKit selected the first matching `com.larian.bg3` window even when BG3 exposed a thin auxiliary map strip before the main game surface.
  - Impact: Capture reported success at 5120×88, the local matcher correctly rejected the strip, and a genuinely open map appeared undetectable.
  - Fix: Rank matching Larian windows by visible pixel area and capture the largest game surface; regression-test the window-selection rule independently of live enumeration order.
- Screen capture forced a Retina-style 2× output size even though BG3's Metal surface already reported its real 2560×1440 render size.
  - Impact: The 2560×1440 game frame occupied only the top-left quarter of a 5120×2880 canvas, so successful alignment coordinates would be divided by two when projected back into the overlay window.
  - Fix: Capture at the selected BG3 window's reported pixel dimensions and regression-test that the capture-size policy is 1:1.

- The level-aware recommender still collapsed the player's plan into one fight card and buried dialogue outcomes across notes, warnings, and preparation.
  - Impact: Selecting a party level did not clearly answer whether to gain XP, clear a mini encounter, attempt a core fight, or choose a specific Honor-safe dialogue option.
  - Fix: Make party level drive a structured plan with a current activity type, safe XP targets, the next core challenge, a level-up gate, and explicit checkpoint-specific dialogue decisions.

- Party level setup required four separate steppers, assigned builds did not count as prepared capabilities, and next-step selection always chose the first pending route row.
  - Impact: Initial setup was slow, build users received redundant preparation warnings, and an under-level party could be parked on a blocked encounter instead of receiving a nearby level-appropriate objective. A naive alternative could also bounce between Wilderness and Underdark.
  - Fix: Add a party-wide quick level selector, treat the selected reviewed build as the member's assumed setup at that level, and select next steps through a level-banded regional route that completes a region before transitioning.

- Manual checkpoint completion existed only near the bottom of the expanded Current tab.
  - Impact: A player who had already finished Nautiloid could reasonably think screenshot validation was required before the assistant would advance.
  - Fix: Promote `Done` to the compact pet action row, share the same safety confirmation between compact and expanded states, and visibly advance to the next deterministic checkpoint immediately after confirmation.

- The first native map-overlay pass normalized coordinates using only the min/max locations of the current region.
  - Impact: Markers could look plausible at one view but drift after real in-game pan or zoom.
  - Fix: Make local ORB/RANSAC artwork registration authoritative and project markers through its recovered screenshot transform; keep region bounds only as an explicit interior/offline fallback.
- The design document stated that positive map registration had been validated live even though the retained evidence only proved synthetic positive alignment and live non-map rejection.
  - Impact: The document overstated completion of a real-game acceptance check.
  - Fix: Corrected the design and LABREPORT to name the outstanding loaded-save map check explicitly; completion now requires observable live positive evidence.
- BG3 detection and ScreenCaptureKit selection initially accepted the generic substring `bg3`.
  - Impact: The rebranded assistant's own `BG3 Honor Mode Assistant` window could satisfy the detector or be selected for capture when the game was closed.
  - Fix: Match Larian's `com.larian.bg3` bundle identifier or explicit Baldur's Gate process/window names, and regression-test that the assistant identity is rejected.

- Shadow Blade was modeled as a standalone class/build even though the requested character was the Bladesinging build.
  - Impact: The spreadsheet and local map exposed an equipment package as if it were a playable character plan.
  - Fix: Replace `PK-SB` with a source-backed Bladesinger build and remove the Shadow Blade package from human-facing build selectors.
- Lockadin remained in the build list after it had already been identified as incompatible with the intended Honor Mode progression.
  - Impact: Humans still had to evaluate and reject a deliberately disabled option.
  - Fix: Remove Lockadin entirely and replace it with the requested Honor-compatible Flamadin guide.
- The first build-guide layout placed all builds, levels, and equipment into one long `Build details` tab.
  - Impact: A player could not quickly scan one character's next level and gear route during a run.
  - Fix: Use one self-contained tab per build with overview, progression, and equipment sections.
- The first batch-created cleric sheet was left with its default name because the script inferred the newest visible tab by position.
  - Impact: The live workbook temporarily had seven valid build tabs and one empty default sheet.
  - Fix: Export verification caught the missing expected tab; the default sheet was renamed, populated, formatted, and reverified.
- Two gear descriptions began with `+1`, which Google Sheets interpreted as formulas during plain-text paste.
  - Impact: The affected cells displayed `#NAME?` instead of equipment advice.
  - Fix: Reworded both descriptions to begin with `Adds 1`, corrected the live cells, and scanned every build tab for formula errors.
- The first draft of `data/build_levels.tsv` had two Monk respec rows with one missing column.
  - Impact: Those rows would have shifted tactical advice into the wrong spreadsheet column.
  - Fix: A TSV shape check caught both rows before upload; the missing feat/skills fields were added.

## 2026-06-01

- The first prototype gated the overlay entirely on automatic game detection but omitted the installed Steam executable identity.
  - Impact: The game could be open while the control window showed no overlay and gave no actionable reason.
  - Fix: Detection now checks app name, executable name, executable path, bundle identifier, window owner, and window title.
  - Workflow change: The control window now shows detection detail and includes a `Force Overlay` debug fallback so overlay failures are not silent.

- The backend was implemented as a separate manual process, so the mac app could show `Backend health: Offline` even though the user had provided `.env`.
  - Impact: Pressing `Ask` failed with `Could not connect to the server`.
  - Fix: The app now starts the local dev backend via `uv run uvicorn app.main:app --host 127.0.0.1 --port 8787` when `/health` is offline.
  - Follow-up fix: The first backend starter tried to open log files before creating them, so the process never launched. It now creates stdout/stderr logs first and writes backend manager logs under the app's Application Support directory.

- The permission model was too implicit.
  - Impact: It looked like missing microphone, keyboard input, or speaker permissions might explain failures.
  - Fix: The control window now states that microphone and keyboard input are not required for this MVP, and speaker output does not need a separate macOS permission.

- The manual `.app` bundle was not signed with a stable bundle identifier.
  - Impact: macOS Screen Recording could be granted to one build, then a later rebuild appeared as a different app identity and reported permission missing.
  - Fix: `mac/scripts/build-app.sh` now signs the bundle with a stable BG3 assistant identifier using the local Apple Development identity when available, and the control window shows the exact permission identity/path.

- Screen Recording status used `CGPreflightScreenCaptureAccess()` as a hard gate.
  - Impact: If the preflight API returned stale or false while actual capture worked, the assistant disabled capture and recording even after the user granted permission.
  - Fix: The assistant now treats a real successful ScreenCaptureKit capture as authoritative, does not disable `Test Capture`, and attempts capture before reporting a permission failure.

- The prototype used obsolete CoreGraphics display capture on a macOS SDK that points screen capture clients to ScreenCaptureKit.
  - Impact: Permission checks and capture behavior could disagree with Apple's current Screen Recording path.
  - Fix: `ScreenCaptureService` now uses `SCShareableContent` plus `SCScreenshotManager.captureImage`.

- Turn log visibility depended only on `isRecording`.
  - Impact: After stopping a test recording or restarting the app, the left turn-log overlay disappeared and it looked like turn logging did not exist.
  - Fix: The retired turn recorder auto-started only when the game, backend, and screen capture were ready; its overlay also remained visible when there was an active log path or existing entries.

- The Screen Recording settings prompt was tied to passive status instead of an actionable capture failure.
  - Impact: The assistant could tell the user to open System Settings even when macOS already showed Screen Recording as granted, because an unverified or stale status was treated as a missing permission.
  - Fix: The settings callout now appears only after an actual ScreenCaptureKit capture attempt fails with a permission/TCC-style error. Passive status refreshes no longer probe capture or surface the callout.

- Automatic turn recording was allowed to trigger ScreenCaptureKit before capture was verified in the current launch.
  - Impact: Reopening the prototype with its game already detected could immediately trigger macOS's own Screen Recording modal, making it look like the app was still prompting even though the custom settings callout had been fixed.
  - Fix: Auto-record now requires a successful capture in the current launch. Manual `Test Capture`, `Ask`, and `Start Recording` remain the explicit paths that can verify capture or surface a real TCC error.
# 2026-07-12 — Misattributed a dev backend to the packaged app

I initially treated port 8787 remaining open after the isolated app quit as a bundled-backend lifecycle failure. Process ancestry showed the listener was actually restarted by a stale pre-rebrand app process, while the packaged backend logged a clean shutdown. For lifecycle assertions, verify executable path and parent process, not only the shared port.
