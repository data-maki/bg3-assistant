# Release Checklist

## Build requirements

- [ ] Set version and build numbers in `mac/BG3Assistant/Resources/Info.plist`.
- [ ] Install a Developer ID Application certificate.
- [ ] Store notarization credentials in a `notarytool` keychain profile.
- [ ] Run the enforced release build:

  ```sh
  cd mac
  NOTARY_PROFILE=bg3-honor-notary \
  REQUIRE_RELEASE_SIGNING=1 \
  ./scripts/build-release.sh
  ```

- [ ] Record and verify the generated ZIP SHA-256.
- [ ] Test the uploaded ZIP on a clean macOS 14+ Apple-silicon account.

## Product smoke test

- [ ] First launch creates only a menu-bar item and native overlay, not a control window.
- [ ] BG3 detection, Launch BG3, Show Overlay, Open Planner, Open Map, Settings, and Quit work.
- [ ] Now, Run, and Party remain usable without an OpenRouter key or Screen Recording permission.
- [ ] Party presents one character at a time and persists level, build, status, and equipment changes.
- [ ] Named Honor runs can be created, renamed, switched, and resumed with independent progress and party state.
- [ ] Done, Skip, Revisit, focus, decisions, and the resolved archive persist after restart.
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

cd ../mac
swift build
BUILD_BACKEND=0 ./scripts/build-app.sh
codesign --verify --deep --strict "BG3 Honor Mode Assistant.app"
```

Run `git diff --check` from the repository root. Keep screenshots and QA evidence in ignored `outputs/`, `qa/`, or `artifacts/` directories.

## Publishing blockers

Public macOS downloads require a Developer ID Application signature and Apple notarization. A locally signed development build is not a substitute.
