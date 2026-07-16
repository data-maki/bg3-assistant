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

- [ ] First launch creates only a menu-bar item and native overlay, not a control window or Dock app.
- [ ] The menu-bar Settings command opens settings inside the native overlay.
- [ ] BG3 detection, Launch BG3, Show Overlay, Open Planner, Open Map, Settings, and Quit work.
- [ ] Now, Run, and Party remain usable without an OpenRouter key or Screen Recording permission.
- [ ] Party presents one character at a time and persists level, build, status, and equipment changes.
- [ ] Named Honor runs can be created, renamed, switched, and resumed with independent progress and party state.
- [ ] Done archives immediately; Skip, Revisit, focus, decisions, and the resolved archive persist after restart.
- [ ] Now shows Danger, Avoid, and Do without preparation or post-fight confirmation checklists.
- [ ] The browser map starts from the app-owned local service and shares the same run state.
- [ ] Guide-only chat and speech input work without an OpenRouter key.
- [ ] An OpenRouter key saves to Keychain, restarts the local service, and enables AI chat.
- [ ] Opening configured AI chat requests Screen Recording only when needed, attaches one BG3-window image, previews/removes it, and sends it only with the next message.
- [ ] No periodic screenshot, recording, map-alignment, mod, telemetry, or game-memory process runs.
- [ ] Launch at Login can be declined or disabled in Settings.
- [ ] A second launch leaves one app owner, one packaged backend, and one listener on port 8787.
- [ ] Quit releases the owned local backend and port 8787.

## Automated verification

```sh
cd backend
uv lock --check
uv run --with pytest pytest

cd ../mac
swift build
BUILD_BACKEND=0 ./scripts/build-app.sh
codesign --verify --deep --strict "BG3 Honor Mode Assistant.app"
bash -n scripts/build-testflight.sh
```

Run `git diff --check` from the repository root. Keep screenshots and QA evidence in ignored `outputs/`, `qa/`, or `artifacts/` directories.

## Direct-download fallback

`scripts/build-release.sh` still creates a Developer ID-signed, notarized ZIP for local or direct-download testing. It is not the primary beta channel while TestFlight distribution is active.
