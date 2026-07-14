# BG3 Honor Mode Assistant Release Checklist

## Required before public download

- [x] Permanent reverse-DNS bundle ID is `com.datamaki.BG3HonorAssistant` in source and the signed package.
- [ ] Install a **Developer ID Application** certificate for the publishing Apple team.
- [ ] Store notarization credentials in a keychain profile for `xcrun notarytool`.
- [ ] Set the final version/build numbers in `mac/BG3Assistant/Resources/Info.plist`.
- [ ] Run the enforced release build:

  ```sh
  cd mac
  NOTARY_PROFILE=bg3-honor-notary \
  REQUIRE_RELEASE_SIGNING=1 \
  ./scripts/build-release.sh
  ```

- [ ] Verify the printed SHA-256 against the uploaded ZIP.
- [ ] Unzip the uploaded artifact on a clean macOS 14+ Apple-silicon account and confirm Gatekeeper opens it normally.

## Product smoke test

- [x] First launch from `/Applications` keeps Visual Memory and Map overlay off, performs no automatic pixel capture for at least 30 seconds, and does not request Screen Recording.
- [x] Enabling a capture feature or choosing a manual capture action shows the in-app explanation only when permission is missing; the granted permanent identity survives relaunch and reports `Pixel access verified` without repeated permission prompts.
- [x] BG3 detection and **Launch BG3** work.
- [x] Pet, planner, level selector, build assignment, and manual Done/Skip/Revisit work.
- [x] Native and localhost state share one SQLite database; legacy JSON migrates once, writes keep bounded revisions, and isolated packaged QA retains progress, L6 party state, builds, run choices, and overlay density across repeated full restarts.
- [x] Any unresolved activity can be focused without erasing the recommendation; Done/Skipped work leaves active phases for Archive, and Revisit restores it.
- [x] Fight completion opens Recover before the next route step; Minimal/Focus/Reference density and the Option-Space hold-to-peek path compile in the signed package.
- [x] Pet is static outside hover; hover timing and all four v2 cardinal look mappings pass native regressions, and the packaged pet exposes its interaction state to accessibility.
- [x] Launching the app twice, including from an extracted ZIP path, leaves one pet owner, one embedded backend, and one listener on port 8787.
- [x] A force-quit orphaning the packaged backend is repaired on relaunch before `/health` is trusted; PID/parent and the 59-step schema are verified.
- [x] Embedded backend reports 19 checkpoints, 59 walkthrough steps, nine builds, 102 level rows, and 72 map markers without the source checkout, Python, or `uv`.
- [x] Full roster persists one custom character plus six origins, projects at most four active members, and excludes camp/dead/unavailable members from readiness without losing their builds.
- [x] Dead/departed transitions require confirmation; terminal/unavailable companions cannot be promoted directly, and story outcomes remain separate idempotent confirmations.
- [x] Open Hand Monk has current-level-compatible Act 1 slot coverage; Warlock–Eldritch Knight has a reviewed early bridge and level-6 respec plan.
- [x] Native and web Route use compact rails with one detail surface; chat receives a deterministic, server-resolved run snapshot.
- [x] Native equipment ownership persists per member, enforces one owner for unique items, reaches chat/readiness and the localhost handoff, and survives restart.
- [x] Ask does not capture a fresh screenshot; optional provider prose cannot replace deterministic Guide fact/Suggestion/Unknown authority.
- [x] Opt-in Visual Memory captures at most one BG3 frame per 30-second interval, deduplicates observations, retains at most 24 entries, and persists text evidence without image bytes.
- [x] A high-confidence completion candidate opens the matching pending step for review but does not change its status until the player presses **Done**; native and chat-context regressions assert progress remains pending.
- [x] With both Visual Memory and Map overlay enabled, one captured frame feeds both paths through the actor-serialized capture service; the installed local-only map pass proved the 30-second gate and clean disable path.
- [x] Marker export derives the current phase/level/build queue, activates the exact labels in the temporary overlay, downloads JSON, and suppresses a confirmed fingerprint.
- [x] Web Party shows one current-level action per named member; Equipment is a separate Act 1 tab with persistent per-member assignments and map handoff.
- [x] Flamadin and Control Martial expose complete Act 1 interim loadouts (11 and 14 recommendations) with effects, icons, acquisition locations, and map handoff even though defining upgrades arrive later.
- [ ] With a real BG3 map open, place the exported pins through the scoped Computer Use flow and screenshot-verify names/positions before clicking **Placed in BG3**.
- [ ] Open a real Wilderness map, confirm visible fight markers, pan once, zoom once, change the BG3 window geometry once, and confirm markers remain aligned after each change.
- [x] Quit the app and confirm its owned local backend releases port 8787.
- [x] Keep the vanilla overlay fully functional without a mod or telemetry feed.
- [x] Exclude the deferred telemetry mod from default tests, packaging validation, and release gates.

## Current 0.1.0 evidence

- Backend tests: 84 vanilla-product tests passed; deferred mod tests are excluded.
- Native model/detector/map/persistence checks: passed.
- Signed app and unzipped copy: strict code-sign verification passed.
- Embedded backend: owned `/health` (PID, parent, packaged state, 59 walkthrough steps), 19 checkpoints, nine builds, 102 level rows, 72 markers, and `/map` passed.
- Retained real Wilderness frame: 132 inliers, confidence 1.0, four on-screen fight targets.
- Current ZIP SHA-256: `5d4cf8c12815f5791ec30fd39331c71f8e4bb6573b38ac1d0ab1259a70581152`.
- Current external blockers: Developer ID Application certificate and notary profile. Gatekeeper correctly rejects the Apple Development build.
- Current live evidence gaps: execute the named custom-marker flow on a real loaded-save map and observe alignment after one pan, zoom, and geometry change.
- Visual Memory provider behavior is contract-tested with a hermetic structured response. The release QA intentionally did not enable it against the player's live BG3 frame; doing so would transmit that frame to the configured provider.

## Deferred future work

The optional telemetry mod is intentionally outside the current test, validation, packaging, and release scope. Its source remains under `mod/` for a future, separately planned effort; it is not a blocker for the vanilla assistant.
