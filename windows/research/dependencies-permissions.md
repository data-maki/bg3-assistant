# Windows Dependencies, Permissions, and Integration Risks

Status: implementation specification

Reviewed: 2026-07-25

## Target platform

- Windows 11 ARM64 and x64/AMD64 only; 32-bit x86 is unsupported.
- Initial OS floor: Windows 11 24H2, build 26100; test serviced releases on both architectures where runners/devices are available.
- Target framework: `net10.0-windows10.0.26100.0`.
- Runtime/package pairs: `win-arm64`/`arm64` and `win-x64`/`x64`; matching `PlatformTarget` and MSIX processor architecture are mandatory.
- WPF application runs at normal user/medium integrity. `requestedExecutionLevel` is `asInvoker`.

The OS floor is support policy, not a technical limitation of each API. Microsoft currently lists 24H2, 25H2, and 26H1 as serviced Windows 11 lines, with 24H2 Home/Pro support ending in October 2026 ([Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)). Re-evaluate the floor at the first release candidate.

There is no 32-bit requirement. The product supports exactly ARM64 and x64/AMD64 with separate RIDs, native dependencies, and MSIX identities. A neutral/AnyCPU native package and Arm64EC are rejected because process/window interop and packaging must be deterministic.

## macOS-to-Windows framework replacements

| Current macOS technology | Windows replacement | Notes |
|---|---|---|
| SwiftUI | WPF XAML, controls, data binding, commands | Port behavior and view hierarchy, not Swift types. |
| AppKit `NSPanel`, `NSWorkspace`, status item | WPF `Window`, HWND/Win32 styles, shell execution, `NotifyIcon` | `HwndSource` is the boundary for messages/styles. |
| CoreGraphics window list/bounds | `EnumWindows`, `GetWindowThreadProcessId`, `DwmGetWindowAttribute`, `SetWindowPos` | No game-memory access. |
| ScreenCaptureKit/CoreGraphics capture | None | Approved Windows MVP exclusion; no screenshot, image attachment, clipboard-image, capture service, or capability ships. |
| AVFoundation + Speech | None | Approved Windows MVP exclusion; no microphone, recognition, dictation, service, or capability ships. |
| Security/Keychain | Win32 Credential Manager: `CredWriteW`, `CredReadW`, `CredDeleteW`, `CredFree` | Generic, device-local user credential. |
| ServiceManagement `SMAppService` | MSIX `windows.startupTask` + `StartupTask` | User-controlled and disabled by default. |
| Foundation `URLSession` | one long-lived .NET `HttpClient` | Direct OpenRouter plus explicitly approved external imports. |
| `Codable` / JSONSerialization | `System.Text.Json` | Shared fixtures pin serialization semantics. |
| `SQLite3` C API | `Microsoft.Data.Sqlite` | Restores the matching ARM64 or AMD64 native SQLite asset. |
| PDFKit | PdfPig | Text extraction only; no renderer/runtime install. |
| HTML text extraction | AngleSharp | Parse downloaded HTML; scripts never execute. |
| `UserDefaults` | SQLite `settings` table | One durable store. |
| `lockf` lock file | per-user named mutex + registered window message | No IPC server or port. |
| StoreKit transaction code | None | Unreferenced legacy code; Windows product has no purchase flow. |
| `BackendProcessManager`/local HTTP backend | None | Unreachable legacy path; deliberately removed. |
| Ollama/local Gemma/Qwen runtime | None | Prohibited by product requirements. |
| Python guide compiler | Existing repository build-time pipeline only | Generated JSON/media are packaged; Python never ships. |

WPF supports transparent/topmost windows directly, and the Win32 extended styles fill the no-activate/tool-window gap ([WPF window overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/), [extended window styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)). Windows Runtime APIs are available from a .NET desktop app through a Windows-versioned target framework; package identity is needed only for the APIs that explicitly require it ([WinRT desktop configuration](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps)).

## NuGet and build dependencies

Pin these audited baselines in `Directory.Packages.props` and commit `packages.lock.json`:

| Package | Baseline on 2026-07-25 | Runtime purpose | License/control |
|---|---:|---|---|
| `Microsoft.Data.Sqlite` | 10.0.10 | SQLite ADO.NET provider and distinct native ARM64/AMD64 SQLite assets | Microsoft; exact transitive native files included in SBOM |
| `AngleSharp` | 1.5.2 | HTML-to-text for build imports | MIT |
| `PdfPig` | 0.1.15 | PDF-to-text for build imports | Apache-2.0; pre-1.0 API, so version stays locked |
| `Microsoft.Windows.CsWin32` | 0.3.298 | Build-time generation for the small Win32 surface | MIT; `PrivateAssets=all`, no runtime dependency |
| `xunit`, test SDK/runner | current locked .NET 10-compatible stable set | Unit/integration tests only | Test projects only |

The public NuGet catalog was checked for these stable baselines during this investigation. `Microsoft.Data.Sqlite` is Microsoft’s lightweight SQLite provider ([provider overview](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/)); CsWin32 generates strongly typed P/Invoke source and does not require a bulky runtime binding ([CsWin32](https://github.com/microsoft/CsWin32)).

Do not add:

- OpenRouter/OpenAI SDKs; raw `HttpClient` and `System.Text.Json` are sufficient.
- a dependency-injection or MVVM framework before a measured need.
- WebView2, Electron, Node, Python, Ollama, a local model, or an application server.
- a keyboard/mouse hook library, process inspection library, or game integration.
- capture, image/clipboard, audio, microphone, speech-recognition, or dictation packages.

Release CI runs `dotnet list package --vulnerable --include-transitive`, produces an SBOM, and fails if the lock file changes unexpectedly. Dependency updates are separate reviewed changes with unit/package smoke tests.

## Required package manifest surface

The packaged WPF process uses `uap10:TrustLevel="mediumIL"` and `uap10:RuntimeBehavior="packagedClassicApp"`. `windowsApp` is for UWP, not this WPF desktop process; Microsoft classifies Desktop Bridge/packaged desktop applications under `packagedClassicApp` ([packaged desktop runtime behavior](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)).

Required declarations:

- `rescap:Capability Name="runFullTrust"` — required for the normal packaged desktop process. It does not mean administrator elevation.
- `desktop:Extension Category="windows.startupTask"` — disabled by default, with the packaged executable and one stable task ID.

`runFullTrust` is a restricted manifest capability, so the Store submission must explain that it is used for the normal WPF desktop/overlay process and Win32 integrations, not elevation or background service access. Partner Center review of that declaration is a release prerequisite.

Not declared:

- `graphicsCaptureProgrammatic`
- `graphicsCaptureWithoutBorder`
- `DeviceCapability Name="microphone"`
- camera, location, documents/pictures/music libraries
- `privateNetworkClientServer`
- `internetClientServer`
- UIAccess, broad file-system access, packaged service, driver, app capture services

A medium-integrity desktop app already has the current user’s normal outbound network rights, so an AppContainer `internetClient` declaration is not required. No privacy-sensitive device access is used.

## Permission and consent matrix

| Feature | OS declaration | When Windows/player is prompted | Denied/blocked behavior |
|---|---|---|---|
| Overlay/topmost window | None beyond normal desktop execution | No prompt | If enterprise policy blocks the app, it cannot run. |
| BG3 process/window detection | None | No prompt | Show “BG3 not detected” and retain manual overlay/planner access. |
| Direct OpenRouter HTTPS | None for mediumIL | No OS prompt; onboarding explicitly explains network use | Guide stays available; chat shows a precise offline/proxy/provider error. |
| Screenshot/image input | None; feature absent | Never | Typed chat remains available. Package tests reject capture/image UI, services, APIs, and capabilities. |
| Microphone/speech | None; feature absent | Never | Typed chat remains available. Package tests reject microphone/speech UI, services, APIs, and capabilities. |
| Start at login | `windows.startupTask`, disabled | Only after the player turns on the setting; Windows may retain final control | Respect `DisabledByUser`; link to Settings > Apps > Startup. |
| OpenRouter key | None | App dialog only, not a Windows permission prompt | Guide works without AI; chat asks for a key. |
| External URLs | None | Default browser/mail app may ask its own questions | Show an open failure; no embedded browser fallback. |

### Approved capture and speech exclusions

Screenshot capture, image attachments, clipboard-image ingestion, microphone access, speech recognition, and dictation are excluded from the Windows MVP. The shipped application therefore needs no capture or microphone consent flow. Source, manifest, dependency, and unpacked-package tests enforce the absence of these surfaces.

### Credential storage

Store the API key as a generic current-user credential:

- Target: `BG3HonorAssistant/OpenRouter`
- User name field: `OpenRouter`
- Blob: UTF-8 API key
- Persist: `CRED_PERSIST_LOCAL_MACHINE`

This persistence makes the item available to the same user’s future logon sessions on the same computer, not other users or roaming devices ([`CREDENTIALW` persistence](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw)). Zero temporary byte buffers after use where practical, redact all `Authorization` headers, and never expose credential content in diagnostics. Settings provides Save, Replace, Test, and Remove; Remove calls `CredDeleteW`.

Credential Manager is outside MSIX package storage. MSIX uninstall cannot be relied on to delete that item, so the app must expose “Remove OpenRouter key” and the player README must instruct security-conscious users to use it before uninstalling.

### Startup

Use a packaged startup task, disabled by default. Call `RequestEnableAsync()` only from the explicit Settings/onboarding toggle after the first normal launch. If Windows returns `DisabledByUser`, do not repeatedly prompt; point to system Startup settings. Microsoft documents that packaged desktop startup tasks require a manifest extension, cannot run before the app’s first launch, and remain user-controlled ([StartupTask](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask?view=winrt-26100)).

Startup launches to the tray without forcing the overlay. The overlay appears only after BG3 detection and the user’s “Show overlay while BG3 is running” setting.

## Networking and import boundaries

Outbound destinations:

- `https://openrouter.ai/api/v1/chat/completions`
- user-selected HTTPS build-import URLs after validation
- user-opened browser links for maps, wiki, legal, mail, and releases
- the HTTPS MSIX/App Installer update host, handled by Windows

The application:

- listens on no TCP/UDP port;
- registers no firewall rule;
- runs no local HTTP server;
- uses the system proxy/TLS stack through `HttpClient`;
- caps OpenRouter and import request/response sizes and timeouts;
- never follows an import redirect automatically.

For every build-import URL and redirect candidate:

1. Require HTTPS, host, and port 443.
2. Resolve all A/AAAA records before connecting.
3. Reject loopback, link-local, private, multicast, unspecified, documentation, benchmark, and otherwise non-public ranges.
4. Connect, then validate every redirect target again with a small redirect limit.
5. Cap download at 5 MB, extracted text at 60,000 characters, and content types to supported text/HTML/PDF.

This is stricter than the current Swift path and is necessary because user-provided URLs cross a local-network trust boundary.

## Signing, Defender, SmartScreen, and antivirus

### Release signing

Every public MSIX must be signed and trusted. Timestamp signatures so installation remains valid after certificate expiry. Keep package identity, publisher subject, and signing identity stable across releases. Microsoft requires MSIX signing and recommends Artifact Signing for production direct distribution; it also documents timestamping and package-integrity enforcement ([MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)).

Preferred order:

1. Microsoft Store MSIX for stable releases: Microsoft re-signs it and avoids SmartScreen download warnings.
2. Azure Artifact Signing Public Trust for direct beta distribution.
3. Traditional OV certificate if Artifact Signing eligibility is unavailable.

Self-signed certificates are development-only.

### SmartScreen reality

A valid non-Store signature identifies the publisher but does not guarantee no warning. SmartScreen uses publisher and file-hash reputation; new signed releases can still be “unrecognized,” while unsigned files rebuild reputation from zero every release. EV certificates no longer bypass this. The Microsoft Store is the only planned channel with no SmartScreen download warning ([SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).

The player documentation must never recommend disabling SmartScreen/Defender or adding an antivirus exclusion.

### False-positive reduction and response

Reduce behavioral risk:

- no obfuscator, packer, self-extractor, process injection, global hooks, driver, elevated helper, service, or downloaded executable;
- no local model/server lifecycle;
- normal signed MSIX layout with deterministic versioned files;
- no writes to BG3, Steam, GOG, Program Files, registry startup keys, or other processes;
- complete publisher/version metadata, SBOM, notices, and reproducible hashes.

Before release:

- run unit/integration/package tests on a clean Windows VM;
- verify signatures with SignTool and `Get-AuthenticodeSignature`;
- scan the installed and packaged artifacts with current Microsoft Defender;
- record SHA-256 hashes and retain the exact signed artifacts.

If Defender flags a clean release, stop rollout and submit the exact signed file as incorrectly detected through Microsoft Security Intelligence; Microsoft documents that good files can be submitted for analysis ([file submission guidance](https://learn.microsoft.com/en-us/defender-office-365/submissions-submit-files-to-microsoft)). Publish the submission ID/status, not a bypass recipe.

## Installation and runtime risks

| Risk | Planned control |
|---|---|
| True exclusive full-screen hides the overlay | Require Windowed/Borderless Windowed; never inject. |
| BG3 runs as administrator | Tell player to run BG3 normally; do not elevate the assistant. |
| Package publisher/certificate mismatch | CI compares manifest Publisher with signing identity before signing. |
| Direct-install SmartScreen reputation | Store stable channel; signed beta; consistent publisher; clear source/hash. |
| Enterprise blocks sideload or OpenRouter | Detect and explain policy-limited state; guide features remain local. |
| Credential survives uninstall | Settings Remove key plus README uninstall step. |
| Package update changes schema | transactional migration, pre-migration database copy, rollback test. |
| Native ARM64/AMD64 asset omitted or contaminated | dual-RID locked restore, recursive publish/MSIX PE inspection, and loaded-module architecture tests. |
| Unsupported 32-bit/Arm64EC request appears | Reject it; never relabel either supported artifact. |

## Permission acceptance gate

The Windows build cannot leave platform validation until:

- the manifest contains only the declared minimum surface;
- a clean architecture-matching Windows 11 environment can install and run without admin or developer mode;
- capture and microphone prompts never occur because the features and capabilities are absent;
- denying startup or Credential Manager access leaves runs/routes/party/builds/gear/acts usable;
- outbound chat works with no inbound firewall rule or local listener;
- Credential Manager contains the key while SQLite/logs/package do not;
- process-monitor evidence shows no BG3 file, memory, save, or injection access;
- signed package/publisher verification passes.
