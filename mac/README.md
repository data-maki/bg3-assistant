# macOS app project

The app you edit is **`mac/BG3Assistant/`**. Its bundled images, plist files, entitlements, and guide data are in `mac/BG3Assistant/Resources/`.

The other items here belong to that same app project:

- `Tests/` contains its Swift tests.
- `Package.swift` defines command-line builds and tests.
- `BG3HonorAssistant.xcodeproj/` and `project.yml` define the Xcode app.

Run commands from the repository root:

```sh
./scripts/macos/validate.sh
./scripts/macos/build-app.sh
open "artifacts/macos/app/BG3 Honor Mode Assistant.app"
```

All generated macOS output lives under the gitignored `artifacts/macos/` directory, never beside the source.
