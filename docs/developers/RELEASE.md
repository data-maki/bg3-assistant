# Release Checklist

The current macOS artifact is a native Swift app with a generated guide JSON and a pinned Ollama runtime. It has no Python/FastAPI companion, hosted authentication, import quota, or configured backend URL. Users explicitly choose Local Qwen or OpenRouter.

## Artifact contract

A releasable `BG3 Honor Mode Assistant.app` contains:

- `Contents/MacOS/BG3HonorAssistant`
- `Contents/Resources/Data/guide-bundle.json`
- Ollama v0.30.10 under `Contents/Resources/ollama`
- The app icon and other native resources

It must not contain:

- `Contents/Resources/backend`
- Python executables, environments, source, or packages
- A bundled `qwen3:4b` model
- An OpenRouter key or `.env` file
- A backend endpoint plist setting

The bundled Ollama archive is pinned in `scripts/macos/build-app.sh`:

```text
version: v0.30.10
sha256: ad8a4d2918ed09480b8160419570602b4f49e48c9e3792efb601c0f54619e48e
```

The user downloads only the `qwen3:4b` model through Settings. Its files live under `~/Library/Application Support/BG3HonorAssistant/OllamaModels`, outside the signed app. OpenRouter always uses `google/gemini-3-flash-preview`; the user's key is stored only in macOS Keychain.

## Release requirements

- macOS 14 or later build host with Swift 6
- Full Xcode 16 or later for distribution workflows
- Developer ID Application certificate for a direct public release
- A `notarytool` Keychain profile for notarization
- Internet access on a clean build to download the pinned Ollama archive
- Up-to-date generated `mac/BG3Assistant/Resources/Data/guide-bundle.json`

The app uses standard HTTPS/TLS and does not implement proprietary encryption. `ITSAppUsesNonExemptEncryption` is `false`; the release owner must still confirm export-compliance answers for the distribution channel.

## Preflight

- [ ] Review and commit all intended `data` changes.
- [ ] Regenerate `guide-bundle.json` after any data or Python loader/catalog change.
- [ ] Confirm the generated guide version and act payloads are the intended release snapshot.
- [ ] Run Swift and backend test suites.
- [ ] Confirm no release credential is exported or stored in repository files.
- [ ] Confirm the build script still pins Ollama exactly to v0.30.10 and the expected SHA-256.
- [ ] Confirm provider model constants remain `qwen3:4b` and `google/gemini-3-flash-preview`.

```sh
./scripts/macos/validate.sh
bash -n scripts/macos/build-app.sh
bash -n scripts/macos/build-release.sh
bash -n scripts/macos/build-testflight.sh

cd backend
uv lock --check
uv run --extra dev pytest
uv run python scripts/export-swift-resources.py

cd ..
git diff --check
git diff --exit-code -- mac/BG3Assistant/Resources/Data/guide-bundle.json
```

The final command intentionally fails when the generated guide was stale before regeneration. Review and commit a legitimate generated diff rather than discarding it.

Backend tests remain part of repository verification because the Python loaders generate the Swift guide resource and the standalone server still exists. They do not imply that Python belongs in the macOS release runtime.

## Build and signing

Build the canonical app bundle:

```sh
./scripts/macos/build-app.sh
```

`build-app.sh` uses a Developer ID Application identity when available, then Apple Development, and otherwise ad-hoc signing. Ad-hoc or development signing is suitable for local verification only.

Create a Developer ID-signed and notarized direct-download ZIP:

```sh
REQUIRE_RELEASE_SIGNING=1 \
NOTARY_PROFILE="BG3 Assistant Notary" \
./scripts/macos/build-release.sh
```

`build-release.sh` verifies that the app has a Developer ID Application authority when `REQUIRE_RELEASE_SIGNING=1`, submits the ZIP with `notarytool`, staples the app, recreates the ZIP, runs Gatekeeper assessment, and prints its SHA-256.

`build-testflight.sh` builds the same artifact, adds the App Store profile and versions, signs executable files in the bundled Ollama runtime with sandbox inheritance, re-signs its Mach-O and Metal libraries with the distribution identity, signs the outer app with sandbox network client/server and audio-input entitlements, and creates the installer package. It rejects exported provider secrets, `.env` files, a missing guide/runtime, or a retired backend directory. The app bundle also includes fan-content attribution and open-source runtime notices. Verify the resulting package with the provider and sandbox smoke tests before upload.

The TestFlight build uploads to App Store Connect by default:

```sh
./scripts/macos/build-testflight.sh
```

Set `UPLOAD_TO_APP_STORE=0` only when an export-only package is intentionally required.

Xcode may finish the upload with `Upload Symbols Failed` warnings for Ollama, ggml, llama.cpp, and MLX binaries. The pinned upstream Ollama archive does not include matching dSYMs for those prebuilt files. These warnings do not reject the build or prevent TestFlight processing; keep uploading the app's own dSYM for symbolicated Swift crash reports.

## Artifact verification

Run these checks against the app produced by `build-app.sh` or extracted from the final ZIP:

```sh
APP="artifacts/macos/app/BG3 Honor Mode Assistant.app"

test -x "$APP/Contents/MacOS/BG3HonorAssistant"
test -f "$APP/Contents/Resources/Data/guide-bundle.json"
cmp mac/BG3Assistant/Resources/Data/guide-bundle.json \
  "$APP/Contents/Resources/Data/guide-bundle.json"

test -x "$APP/Contents/Resources/ollama/ollama" || \
  test -x "$APP/Contents/Resources/ollama/bin/ollama"
test ! -e "$APP/Contents/Resources/backend"
test -z "$(/usr/bin/find "$APP" -name '*.py' -print -quit)"
test -z "$(/usr/bin/find "$APP" -name '.env' -print -quit)"

printf '%s  %s\n' \
  'ad8a4d2918ed09480b8160419570602b4f49e48c9e3792efb601c0f54619e48e' \
  'artifacts/macos/build/swift/ollama-darwin-v0.30.10.tgz' | shasum -a 256 -c -

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP"
```

For a public direct release, inspect `Info.plist` to confirm it has no backend endpoint setting. Inspect `codesign` output for the expected Developer ID Application authority and successful hardened-runtime signing, then run Gatekeeper against the notarized app:

```sh
spctl --assess --type execute --verbose=2 "artifacts/macos/app/BG3 Honor Mode Assistant.app"
```

This assessment is expected to fail for an ad-hoc local build. Verify the notarization result and stapled ticket on the exact artifact being distributed.

Inspect the final app contents manually as well. The runtime archive checksum proves which Ollama distribution was used; the bundle inspection proves no separate model or backend directory was accidentally added.

## Provider smoke test

- [ ] A fresh install shows no configured provider and does not send an AI request until the user chooses one.
- [ ] Selecting Local Qwen starts only the bundled Ollama runtime on `127.0.0.1:11435` when status, download, chat, or import needs it.
- [ ] The app does not start a listener for a Python/backend companion.
- [ ] Download Qwen3 4B stores model data under Application Support, not inside the app bundle.
- [ ] On a clean model directory, Ollama's model list contains `qwen3:4b` after the download.
- [ ] Local chat and URL import use `qwen3:4b`; local chat does not offer or send a screenshot.
- [ ] Quitting the app stops the Ollama process it started and releases port 11435.
- [ ] Selecting OpenRouter without a key reports setup required and does not switch to Local Qwen.
- [ ] Saving an OpenRouter key creates the channel-specific Keychain item (`com.datamaki.BG3HonorAssistant.openrouter.direct` or `.appstore`) with account `api-key`, then verifies it can be read back.
- [ ] The key does not appear in `state.sqlite3`, `imported-builds.json`, logs, app resources, process arguments, or environment-based build settings.
- [ ] Removing the key deletes the Keychain item and leaves OpenRouter unavailable until another key is saved.
- [ ] OpenRouter chat and import call `google/gemini-3-flash-preview` directly from Swift.
- [ ] A failed provider request is visible. Chat may show clearly labelled bundled-guide advice, but neither chat nor import silently calls the other provider.
- [ ] There is no hosted account or usage-limit UI in the release flow.

For a clean local-model check, use a disposable macOS account or back up and remove the app's Application Support directory before launch. Do not delete a tester's existing runs or models during routine upgrade testing.

## Import smoke test

- [ ] A supported public HTML, plain-text, or PDF guide is downloaded by Swift and sent only to the selected provider.
- [ ] Credential-bearing, localhost, `.local`, loopback, private IPv4 literal, oversized, failed, and unreadable sources are rejected.
- [ ] The structured result contains explicit `pointBuyScores`, `bonusTwo`, and `bonusOne`.
- [ ] The importer rejects duplicate bonuses, a non-27-point base spread, duplicate/out-of-range character levels, and an invalid level-12 class total that cannot be normalized from level rows.
- [ ] Final starting scores equal point buy plus the selected +2 and +1.
- [ ] A recoverable final split is deterministically reconstructed from exact class-level maxima rather than accepted as model prose.
- [ ] The imported build is marked for player verification, saved to `imported-builds.json`, and remains available after relaunch.
- [ ] Member-specific import asks for replacement confirmation when required and never changes roster membership.
- [ ] Import failure does not persist a partial build or switch providers.

## Product smoke test

- [ ] First launch creates the menu-bar item and native overlay.
- [ ] BG3 detection, Launch BG3, Show Overlay, Open Planner, Settings, and Quit work.
- [ ] Now, Route, Party, Loadout, and Act load from the bundled guide without an AI provider or network request.
- [ ] Named Honor runs can be created, renamed, switched, and resumed with independent progress and party state.
- [ ] Done, Skip, Revisit, focus, decisions, and resolved history persist after restart.
- [ ] Party guidance shows the current/latest reviewed step, choices, tactics, and setup-due state without future-level clutter.
- [ ] Character detail shows point buy, +2/+1, final values, and later ability sources distinctly.
- [ ] Every reviewed setup recipe spends exactly 27 points, uses distinct bonuses, and derives matching final values.
- [ ] Loadout contention, manual assignment, confirmed ownership, and act-scoped equipment remain deterministic after restart.
- [ ] Act transition requires equipment review and records accepted route consequences in the locked ledger.
- [ ] Act 2 route guidance remains unavailable and normal advancement stays locked while its route coverage is unavailable.
- [ ] Map opens the selected act's external generated `mapUrl` in the default browser; no local map service is started.
- [ ] OpenRouter screenshot capture requests permission only when needed, previews/removes one attachment, and sends it only with the next message.
- [ ] Local Qwen never receives an image.
- [ ] Speech input works with the documented microphone and Speech Recognition permissions.
- [ ] No periodic screenshot, recording, map alignment, mod, telemetry, game-memory reader, or save reader runs.
- [ ] Launch at Login can be declined or disabled.
- [ ] Settings -> Report a Bug opens a message addressed to `jcllobet@gmail.com`.

Keep screenshots and QA evidence in ignored `outputs/`, `qa/`, or `artifacts/` directories.
