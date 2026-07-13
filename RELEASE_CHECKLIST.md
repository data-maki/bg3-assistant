# BG3 Honor Mode Assistant Release Checklist

## Required before public download

- [ ] Choose the permanent reverse-DNS bundle ID; do not publish `com.local.BG3HonorAssistant`.
- [ ] Install a **Developer ID Application** certificate for the publishing Apple team.
- [ ] Store notarization credentials in a keychain profile for `xcrun notarytool`.
- [ ] Set the final version/build numbers in `mac/BG3Assistant/Resources/Info.plist`.
- [ ] Run the enforced release build:

  ```sh
  cd mac
  BUNDLE_ID=com.yourcompany.BG3HonorAssistant \
  NOTARY_PROFILE=bg3-honor-notary \
  REQUIRE_RELEASE_SIGNING=1 \
  ./scripts/build-release.sh
  ```

- [ ] Verify the printed SHA-256 against the uploaded ZIP.
- [ ] Unzip the uploaded artifact on a clean macOS 14+ Apple-silicon account and confirm Gatekeeper opens it normally.

## Product smoke test

- [x] First launch explains Screen Recording; after permission and relaunch, capture becomes `Granted • capture active` automatically while BG3 is visible. **Verify Capture Now** also succeeds as an optional diagnostic.
- [x] BG3 detection and **Launch BG3** work.
- [x] Pet, planner, level selector, build assignment, manual Done/Skip/Revisit, and local persistence work.
- [x] Pet is static outside hover; hover timing and all four v2 cardinal look mappings pass native regressions, and the packaged pet exposes its interaction state to accessibility.
- [x] Launching the app twice, including from an extracted ZIP path, leaves one pet owner, one embedded backend, and one listener on port 8787.
- [x] Embedded backend reports 19 checkpoints, eight builds, and 56 map markers without the source checkout, Python, or `uv`.
- [x] Marker export derives the current phase/level/build queue, activates the exact labels in the temporary overlay, downloads JSON, and suppresses a confirmed fingerprint.
- [x] Web Party shows one current-level action per named member; Equipment is a separate Act 1 tab with persistent per-member assignments and map handoff.
- [ ] With a real BG3 map open, place the exported pins through the scoped Computer Use flow and screenshot-verify names/positions before clicking **Placed in BG3**.
- [ ] Open a real Wilderness map, confirm visible fight markers, pan once, zoom once, change the BG3 window geometry once, and confirm markers remain aligned after each change.
- [x] Quit the app and confirm its owned local backend releases port 8787.

## Current 0.1.0 evidence

- Backend tests: 43 passed.
- Native model/detector/map/persistence checks: passed.
- Signed app and unzipped copy: strict code-sign verification passed.
- Isolated embedded backend: `/health`, 19 checkpoints, eight builds, 56 markers, and `/map` passed.
- Retained real Wilderness frame: 132 inliers, confidence 1.0, four on-screen fight targets.
- Current ZIP SHA-256: `478846399daf2332919d1e5fb8023e3a6e3cbef168916c1f84b7eedaae5b7c85`.
- Current external blockers: permanent bundle ID, Developer ID Application certificate, and notary profile.
- Current live evidence gap: execute the named custom-marker flow on a real loaded-save map, then observe alignment after one pan and zoom.
