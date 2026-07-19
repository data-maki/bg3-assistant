# Release Checklist

TestFlight is the primary beta distribution path. The app remains a Swift package with a keyless bundled Python companion; release packaging does not require a checked-in Xcode project.

## TestFlight requirements

- Full Xcode 16 or later selected with `xcode-select`
- Apple Distribution certificate
- Mac Installer Distribution certificate
- Mac App Store provisioning profile for `com.datamaki.BG3HonorAssistant`
- App record and tester group in App Store Connect
- Transporter installed from the Mac App Store
- An HTTPS hosted backend with `OPENROUTER_API_KEY` set only in its server environment
- Apple root certificates downloaded from the Apple PKI site
- A durable hosted volume for the authentication quota database

The app uses standard HTTPS/TLS and does not implement proprietary encryption. `ITSAppUsesNonExemptEncryption` is set to `false`; the release owner must confirm the export-compliance answers in App Store Connect for every release.

## Hosted backend

Deploy `backend/app` behind an HTTPS ingress. On that server, create `backend/.env` with at least:

```dotenv
BG3_BACKEND_MODE=hosted
OPENROUTER_API_KEY=...
OPENROUTER_MODEL=google/gemini-3-flash-preview
EXA_API_KEY=...
BG3_APPSTORE_BUNDLE_ID=com.datamaki.BG3HonorAssistant
BG3_APPSTORE_ENVIRONMENT=Sandbox
BG3_APPLE_ROOT_CA_DIR=/run/bg3/apple-roots
BG3_APPLE_ONLINE_CHECKS=true
BG3_AUTH_TOKEN_SECRET=<at-least-32-random-bytes>
BG3_SUBJECT_HMAC_SECRET=<different-stable-32-byte-secret>
BG3_AUTH_TOKEN_TTL_SECONDS=3600
BG3_USAGE_DB_PATH=/var/lib/bg3/usage.sqlite3
BG3_BUILD_IMPORT_LIFETIME_LIMIT=30
BG3_IMPORT_PROCESSING_LEASE_SECONDS=600
```

Download and store the DER certificates from Apple's [PKI page](https://www.apple.com/certificateauthority/), including Apple Inc. Root, Apple Root CA - G2, and Apple Root CA - G3. Do not set `BG3_UPSTREAM_BACKEND_URL` on the hosted server; that variable is injected only into the packaged local companion. TestFlight requires `Sandbox`. A later App Store production deployment must use `Production`, set the numeric `BG3_APPSTORE_APPLE_ID`, and use a separate origin, secrets, and usage database. Keep the processing lease longer than the hosted import timeout so only interrupted jobs are reclaimed.

The hosted process exposes authenticated `/v1/*` routes and hides map, catalog, and run-state routes. A local development server can be started with `BG3_BACKEND_MODE=local uv run uvicorn app.main:app --host 127.0.0.1 --port 8787`. Production needs the platform bind address expected by its HTTPS ingress. Keep `BG3_SUBJECT_HMAC_SECRET` stable or existing users will receive new quota identities.

## Build and upload

```sh
cd mac
BG3_BACKEND_URL=https://assistant.example.com \
APP_STORE_PROFILE="$HOME/Downloads/BG3_Honor_Assistant.provisionprofile" \
APP_STORE_INSTALLER_IDENTITY="Mac Installer Distribution: Example (TEAMID)" \
BUILD_NUMBER=2 \
./scripts/build-testflight.sh
```

`BG3_BACKEND_URL` can instead be set in the repository-root `.env`; an exported build variable takes precedence. Remote values must be an HTTPS origin without credentials, a path, query, or fragment. `BUILD_NUMBER` must increase for every App Store Connect upload. The script defaults to a UTC timestamp when it is omitted. It derives the main app's App Sandbox entitlements from the provisioning profile, adds microphone and networking access, and signs the keyless bundled companion as an inheriting child process.

The TestFlight script fails if `RELEASE_OPENROUTER_API_KEY`, `OPENROUTER_API_KEY`, or `EXA_API_KEY` is exported, or if any `.env` file appears in the app bundle. The provider keys belong only in the hosted backend's deployment environment.

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
- [ ] The browser map starts from the app-owned local companion, uses the same Party hierarchy and recipes, preserves unknown/native member fields, and native reloads browser edits before its next write.
- [ ] The Act 1 gate requires every relevant equipment item to be marked obtained or missed, records unresolved route consequences, and cannot return to Act 1 after confirmation.
- [ ] Act 2 loads only `data/gear/act2.tsv` equipment, opens the Shadow-Cursed Lands map reference, and does not expose the Act 1 route or chat as Act 2 guidance.
- [ ] The Act 2 to Act 3 gate remains locked while Act 2 route coverage is unavailable.
- [ ] Guide-only chat and speech input work when the hosted backend is unavailable.
- [ ] No provider-key field is shown anywhere in the app.
- [ ] The hosted backend enables AI chat and build import without putting a provider key in the app bundle.
- [ ] TestFlight AppTransaction verification authenticates without account or key-entry UI.
- [ ] Build import shows the remaining lifetime quota; attempts 1-30 work and attempt 31 returns the quota message.
- [ ] Retrying one idempotency key does not consume another import slot.
- [ ] A public HTML/text/JSON/PDF build URL produces exactly one validated Gemini 3 Flash build with a legal derived creation recipe, persists it, and exposes it to native and browser Party without changing membership.
- [ ] Loadout imports reject localhost/private-network, credential-bearing, oversized, nonstandard-port, and unsupported-file URLs.
- [ ] Opening configured AI chat requests Screen Recording only when needed, attaches one BG3-window image, previews/removes it, and sends it only with the next message.
- [ ] No periodic screenshot, recording, map-alignment, mod, telemetry, or game-memory process runs.
- [ ] Launch at Login can be declined or disabled in Settings.
- [ ] A second launch leaves one app owner, one packaged backend, and one listener on port 8787.
- [ ] Quit releases the owned local backend and port 8787.
- [ ] The packaged `BG3BackendURL` exactly matches the intended HTTPS backend.
- [ ] The final app and `.pkg` contain no `.env`, OpenRouter key, or Exa key.
- [ ] Settings → Report a Bug opens a message addressed to `jcllobet@gmail.com`.

## Automated verification

```sh
cd backend
uv lock --check
uv run --extra dev pytest

cd ../mac
swift build
BG3_BACKEND_URL=https://assistant.example.com BUILD_BACKEND=0 ./scripts/build-app.sh
codesign --verify --deep --strict "BG3 Honor Mode Assistant.app"
/usr/libexec/PlistBuddy -c 'Print :BG3BackendURL' "BG3 Honor Mode Assistant.app/Contents/Info.plist"
bash -n scripts/build-testflight.sh
```

`BUILD_BACKEND=0` requires a freshly built `backend/dist/bg3-honor-backend`; omit it on a clean checkout. Before public beta access, add ingress IP throttling and request-size limits, verify authorization and AppTransaction bodies are redacted from logs, and enforce egress denial for private, link-local, and cloud-metadata networks.

Run `git diff --check` from the repository root. Keep screenshots and QA evidence in ignored `outputs/`, `qa/`, or `artifacts/` directories.

## Direct-download fallback

`scripts/build-release.sh` still creates a Developer ID-signed, notarized ZIP for local or direct-download testing. It is not the primary beta channel while TestFlight distribution is active.
