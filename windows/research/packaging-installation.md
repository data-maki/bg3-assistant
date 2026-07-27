# Windows Packaging and Installation

Status: planned release design; no downloadable Windows binary exists yet

Reviewed: 2026-07-25

## Player-facing outcome

A normal player downloads or Store-installs the package matching the computer: native ARM64 or x64/AMD64. Each package contains only its matching desktop executable, .NET runtime, SQLite native library, guide, images, generated catalogs, and notices. The player does **not** install Visual Studio, the .NET runtime, Python, Node, Ollama, a local model, a server, or a BG3 mod.

Use separate self-contained `.NET 10` `win-arm64` and `win-x64` publishes inside separately labeled MSIX packages. Validate each package before any optional bundle. MSIX gives stable identity, clean install/uninstall, update support, and the packaged startup API ([MSIX overview](https://learn.microsoft.com/en-us/windows/msix/overview/)).

## Distribution channels

### Stable — Microsoft Store (preferred)

- Publish independently validated ARM64 and x64 MSIX packages through Partner Center; bundle only after both validate.
- Store signs/re-signs the package, provides install/update UX, and avoids SmartScreen download warnings.
- The listing states Windows 11 ARM64 and x64/AMD64, OpenRouter key optional for AI chat, no mod integration, no local AI runtime, and Windowed/Borderless Windowed requirement.

This is the lowest-friction player path and Microsoft’s recommended option for most new apps ([distribution choice](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path), [code-signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)).

### Beta — signed direct App Installer feed

Publish three immutable HTTPS artifacts:

```text
 releases/windows/<version>/
   BG3HonorAssistant_<version>_arm64.msix
   BG3HonorAssistant_<version>_x64.msix
   BG3HonorAssistant_<version>_arm64.msix.sha256
   BG3HonorAssistant_<version>_x64.msix.sha256
   BG3HonorAssistant_<version>.sbom.spdx.json

releases/windows/
   BG3HonorAssistant.appinstaller
```

The `.appinstaller` file points to the signed MSIX and checks for updates when the app launches. App Installer is built into Windows 11 and lets users open packages without development tools ([App Installer](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-root)). Microsoft’s current guidance says the browser `ms-appinstaller:` protocol is disabled by default, so the website/GitHub release must offer a normal `.appinstaller` download that the player opens ([publish an app](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app)).

Use the 2021 App Installer schema:

- check on launch;
- at most once every 24 hours;
- show an update prompt;
- do not block launch for ordinary updates;
- allow Windows to apply updates and repair package files.

For a critical security release, publish an intentionally reviewed feed update that blocks activation only after a safe grace period. Do not add a custom updater executable.

## Package identity and versioning

Reserve one identity before implementation proceeds:

- Name: `BG3HonorAssistant`
- Display name: `BG3 Honor Assistant`
- Publisher: exact Partner Center or signing-certificate subject
- Architecture: exactly `arm64` or `x64`, matching the payload and filename
- Version: four-part numeric MSIX version, monotonically increasing

Keep Name and Publisher constant across every update. Direct beta and Store stable should use separate package identities if both may be installed simultaneously; otherwise use one identity/channel to avoid update ownership conflicts.

The first build milestone must select the real Publisher value. Until then, manifests use a documented development identity only. CI fails if:

- the package version is not greater than the previous feed version;
- manifest Publisher does not match the reserved Store identity or direct-signing certificate subject;
- runtime identifier, package architecture, PE headers, native assets, or filename do not all match;
- a direct release lacks a valid trusted package signature/timestamp or any release contains forbidden runtime content.

## Installed artifact layout

Conceptual read-only package:

```text
  BG3HonorAssistant/
   BG3HonorAssistant.exe
   BG3HonorAssistant.*.dll
    Microsoft.Data.Sqlite / matching ARM64 or AMD64 SQLite runtime files
   self-contained .NET runtime files
   Data/
     guide-bundle.json
     spell-catalog.json                 # if split from generated source
   Assets/
     AppIcon/
     CompanionPortraits/
     ItemIcons/
     BuildOptionIcons/
     twilight-cleric.webp
   THIRD_PARTY_NOTICES.md
   PRIVACY.md
```

The exact MSIX VFS projection can be simplified by placing app files at package root if the SDK packaging project prefers it. The invariants are:

- all package content is read-only at runtime;
- resources are addressed through package-relative resource APIs;
- no secret appears in package content;
- no Python, Node, Ollama, model file, backend executable, localhost configuration, service, driver, or mod file exists;
- resource count/hash validation covers the guide, 11 portraits, 51 item icons, 697 build-option icons, pet art, app icons, and notices.

Per-user writable data lives in the package LocalState:

```text
 %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalState\
   state.sqlite3
   state.sqlite3-wal
   state.sqlite3-shm
   logs\
```

OpenRouter credentials live in Windows Credential Manager, not this directory.

## Build and packaging pipeline

### Continuous integration

Use a two-architecture Windows matrix: native x64 Windows CI executes the x64 tests; ARM64 Windows executes ARM64 tests. Cross-building alone is insufficient.

1. Restore the pinned .NET 10 SDK and locked NuGet graph.
2. Validate/generate shared guide data with the existing repository pipeline.
3. Build `Release` for the explicit architecture and execute all unit/integration tests on a matching process ISA.
4. `dotnet publish` self-contained `win-arm64` or `win-x64` with trimming disabled initially.
5. Build the matching MSIX and recursively inspect its manifest, PE/CLR/native content, and complete file inventory before and after unpack.
6. Produce SBOM, notices, SHA-256, and unsigned test artifact.

Trimming is disabled because WPF/XAML, serialization, and WinRT interop are reflection-sensitive; package size is a lower risk than a missing runtime path. ReadyToRun can be evaluated only after measuring launch/package impact.

### Release candidate

1. Install the unsigned/self-signed package only on disposable development VMs.
2. Pass the clean-machine and real-BG3 matrix.
3. Freeze the candidate. For direct beta, sign/timestamp it with Artifact Signing/OV. For stable, submit it for Microsoft Store certification/signing.
4. Verify the direct package signature/publisher or the Store-delivered package identity.
5. Install the exact signed artifact on matching Windows 11 architecture. Physical ARM64 is mandatory release evidence; x64 CI and x64-on-ARM64 emulation do not replace the native-x64 physical release gate.
6. Scan the delivered bytes with current Defender, record hashes/SBOM, then publish the direct feed or complete the Store rollout.

Windows requires deployable MSIX packages to be signed and trusted; timestamping preserves signature validity after certificate expiry ([MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)). Artifact Signing has first-party CI integrations and is the recommended direct-distribution signing service when eligible.

## Installation flows

### Store installation

1. Player opens the Microsoft Store listing.
2. Selects **Install**.
3. Selects **Open** after Windows finishes.

### Direct beta installation

1. Player downloads `BG3HonorAssistant.appinstaller` from the canonical HTTPS release page.
2. Opens the downloaded file.
3. Verifies the displayed publisher and source, then selects **Install**.
4. Selects **Launch**.

Neither flow uses PowerShell, Command Prompt, developer mode, certificate import, source checkout, or a runtime installer. A self-signed package is never presented as a public beta.

## First launch

First launch is a normal WPF onboarding window, not an elevated installer step:

1. Explain overlay-only behavior, no mod/game-file access, and the Windowed/Borderless Windowed requirement.
2. Choose fresh or mid-run, difficulty, spoiler policy, position/party/level state.
3. Choose guide-only mode or add an OpenRouter API key.
4. Optionally enable launch at login; Windows remains the final authority.
5. Finish onboarding and leave the app in the tray.

Permission timing:

- No screen-capture or microphone prompt ever appears; those features, controls, services, and capabilities are excluded from the Windows MVP.
- Startup enablement is requested only after the player turns on its toggle.

If the player adds an OpenRouter key, write it directly to Credential Manager and read it back to confirm local storage. A separate **Test connection** makes a small explicit OpenRouter request; saving a key does not silently spend credits.

## Starting with BG3

The app can be started before or after BG3:

- At startup it sits in the tray and polls/listens for `bg3.exe` or `bg3_dx11.exe`.
- When a valid BG3 window appears and the setting is enabled, it positions the overlay.
- **Launch BG3** opens Steam app 1086940; GOG players launch from GOG Galaxy or their shortcut.
- BG3 must be Windowed or Borderless Windowed for a reliable non-injected overlay.
- If the game is elevated, show a diagnostic asking the player to restart BG3 normally; never elevate the assistant.

## Updates and migrations

Store updates use Store servicing. Direct beta updates use App Installer’s launch check ([automatic updates](https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview)). Updates preserve package identity and LocalState.

On first launch after update:

1. Acquire the single-instance mutex.
2. Read schema and guide versions.
3. Copy `state.sqlite3` to a timestamped migration backup if a destructive schema migration is pending.
4. Run migrations in one transaction.
5. Apply the existing guide-version archive/new-run behavior if shared guide compatibility requires it.
6. Start the UI only after migration commits.

Keep one prior database backup and delete older migration backups only after a later successful launch. Package downgrade is unsupported; data migrations must fail closed with a recovery message and path to the retained backup.

MSIX supports differential package updates where possible, so unchanged bundled media does not necessarily require full redownload ([app package updates](https://learn.microsoft.com/en-us/windows/msix/app-package-updates)).

## Uninstall

Normal uninstall:

1. Optional but recommended: Settings > AI > **Remove OpenRouter key**.
2. Windows Settings > Apps > Installed apps > BG3 Honor Assistant > **Uninstall**.

MSIX removes package files, registrations, and package LocalState. The app installs no service, driver, scheduled task, firewall rule, BG3 mod, or game file, so there is no custom uninstaller.

The Credential Manager item is outside package storage and can survive uninstall. The README must explain how to remove `BG3HonorAssistant/OpenRouter` manually from Control Panel > Credential Manager > Windows Credentials if the app was already uninstalled. Do not add a custom uninstall action solely for that external credential.

The initial parity port does not add a player-facing run export/import feature. Uninstall therefore removes local runs; the README must warn about that before the player confirms uninstall.

## SmartScreen and installation trust

The Store stable channel is the only planned route that reliably avoids SmartScreen download warnings. A new, validly signed direct beta can still show “unrecognized app” until publisher/file reputation develops. Signing every release with the same verified identity allows publisher reputation to accumulate; EV no longer provides an automatic bypass ([SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).

Release pages provide:

- exact version and release notes;
- verified publisher name;
- SHA-256 for the signed MSIX;
- direct link to the canonical HTTPS host;
- privacy/security documentation;
- no instruction to disable Defender or bypass enterprise policy.

If Defender flags a release, pause it and submit the signed artifact to Microsoft for analysis. Do not tell players to create antivirus exclusions.

## Release acceptance checklist

- Clean matching-architecture Windows 11 installs from Store or `.appinstaller` without developer tools/admin.
- Package launches with network disconnected; guide and persistence still work.
- OpenRouter chat works directly when a valid key/network are available.
- No process listens on a port and no firewall rule/service/mod/runtime is installed.
- Startup task is off by default and user-controlled.
- Update preserves runs/settings/key and passes schema/guide migrations.
- Uninstall removes package/app data; documented key-removal path is accurate.
- Signed publisher, timestamp, hashes, SBOM, and Defender scan are recorded.
- Package inventory contains every required asset and none of the forbidden runtimes.
- Every artifact claims only its exact architecture; 32-bit x86, Arm64EC, neutral native, and cross-architecture contamination are rejected.
