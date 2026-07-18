# Release Checklist

TestFlight is the primary beta distribution path. The app remains a Swift package with a bundled Python service; release packaging does not require a checked-in Xcode project.

## TestFlight requirements

- Full Xcode 16 or later selected with `xcode-select`
- Apple Distribution certificate
- Mac Installer Distribution certificate
- Mac App Store provisioning profile for `com.datamaki.BG3HonorAssistant`
- App record and tester group in App Store Connect
- Transporter installed from the Mac App Store

The app uses standard HTTPS/TLS and does not implement proprietary encryption. `ITSAppUsesNonExemptEncryption` is set to `false`; the release owner must confirm the export-compliance answers in App Store Connect for every release.

## Build and upload

```sh
cd mac
APP_STORE_PROFILE="$HOME/Downloads/BG3_Honor_Assistant.provisionprofile" \
APP_STORE_INSTALLER_IDENTITY="Mac Installer Distribution: Example (TEAMID)" \
BUILD_NUMBER=2 \
./scripts/build-testflight.sh
```

`BUILD_NUMBER` must increase for every App Store Connect upload. The script defaults to a UTC timestamp when it is omitted. It derives the main app's App Sandbox entitlements from the provisioning profile, adds microphone and localhost networking access, and signs the bundled backend as an inheriting child process.

Open the generated `.pkg` in Transporter, deliver it to App Store Connect, wait for processing, and add the build to the internal TestFlight group. Complete beta app review before inviting external testers when App Store Connect requires it.

## Product smoke test

- [ ] First launch creates the menu-bar item and native overlay, and the HM app icon appears in the Dock while the app is running.
- [ ] The menu-bar Settings command opens settings inside the native overlay.
- [ ] BG3 detection, Launch BG3, Show Overlay, Open Planner, Open Map, Settings, and Quit work.
- [ ] Now, Run, Party, Loadout, and Act remain usable without an OpenRouter key or Screen Recording permission.
- [ ] Party guidance fits all four active members at a glance, showing the current or latest reviewed step, choices, one-line tactics, and setup-due state without future-level clutter.
- [ ] Manage party members moves known members between Active, Camp, and Unrecruited; moving into a full party asks which active member to replace.
- [ ] Character detail shows the exact active point-buy, +2/+1, and final BG3 values inline, with later boosts and progression available as an expansion.
- [ ] Every reviewed creation/respec recipe spends exactly 27 points, uses distinct +2/+1 bonuses, names the first class/order, and shows ASI, feat, permanent, equipment, and consumable sources.
- [ ] Reset character plan is confirmed, clears build-specific ability/setup and gear-planning state, leaves permanent rewards only when replacing a build, and offers a one-step Undo.
- [ ] Named Honor runs can be created, renamed, switched, and resumed with independent progress and party state.
- [ ] Done archives immediately; Skip, Revisit, focus, decisions, and the resolved archive persist after restart.
- [ ] Now shows Danger, Avoid, and Do without preparation or post-fight confirmation checklists.
- [ ] The browser map starts from the app-owned local service, uses the same Party hierarchy and recipes, preserves unknown/native member fields, and native reloads browser edits before its next write.
- [ ] The Act 1 gate requires every relevant equipment item to be marked obtained or missed, records unresolved route consequences, and cannot return to Act 1 after confirmation.
- [ ] Act 2 loads only `data/gear/act2.tsv` equipment, opens the Shadow-Cursed Lands map reference, and does not expose the Act 1 route or chat as Act 2 guidance.
- [ ] The Act 2 to Act 3 gate remains locked while Act 2 route coverage is unavailable.
- [ ] Guide-only chat and speech input work without an OpenRouter key.
- [ ] An OpenRouter key saves to Keychain, restarts the local service, and enables AI chat.
- [ ] Import without a key shows a focused inline key field; saving the key continues the URL import and preserves the target character assignment.
- [ ] A public HTML/text/JSON/PDF build URL produces exactly one validated Gemini 3 Flash build with a legal derived creation recipe, persists it, and exposes it to native and browser Party without changing membership.
- [ ] Loadout imports reject localhost/private-network, credential-bearing, oversized, nonstandard-port, and unsupported-file URLs.
- [ ] Opening configured AI chat requests Screen Recording only when needed, attaches one BG3-window image, previews/removes it, and sends it only with the next message.
- [ ] No periodic screenshot, recording, map-alignment, mod, telemetry, or game-memory process runs.
- [ ] Launch at Login can be declined or disabled in Settings.
- [ ] A second launch leaves one app owner, one packaged backend, and one listener on port 8787.
- [ ] Quit releases the owned local backend and port 8787.

## Automated verification

```sh
cd backend
uv lock --check
uv run --extra dev pytest

cd ../mac
swift build
BUILD_BACKEND=0 ./scripts/build-app.sh
codesign --verify --deep --strict "BG3 Honor Mode Assistant.app"
bash -n scripts/build-testflight.sh
```

Run `git diff --check` from the repository root. Keep screenshots and QA evidence in ignored `outputs/`, `qa/`, or `artifacts/` directories.

## Direct-download fallback

`scripts/build-release.sh` still creates a Developer ID-signed, notarized ZIP for local or direct-download testing. It is not the primary beta channel while TestFlight distribution is active.
