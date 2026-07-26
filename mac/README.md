# macOS app project

The app you edit is **`mac/BG3Assistant/`**. Shared images and guide data, plus the packaging files consumed by the app builds, are in the repository-root **`Resources/`** directory.

The other items here belong to that same app project:

- `Tests/` contains its Swift tests.
- `Package.swift` defines command-line builds and tests.
- `BG3HonorAssistant.xcodeproj/` and `project.yml` define the Xcode app.

Run commands from the repository root:

```sh
./scripts/macos/validate.sh
./scripts/macos/build-app.sh
open "artifacts/macos/app/BG3 Overlay.app"
```

All generated macOS output lives under the gitignored `artifacts/macos/` directory, never beside the source.
