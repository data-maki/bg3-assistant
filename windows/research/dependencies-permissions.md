# Windows Dependencies, Permissions, and Integration Risks

Status: implementation specification

Reviewed: 2026-07-25

## Target platform

- Windows 11 x86-64/AMD64 only.
- Initial OS floor: Windows 11 24H2, build 26100; test 24H2, 25H2, and 26H1 x64 while each is serviced.
- Target framework: `net10.0-windows10.0.26100.0`.
- Runtime/package: `win-x64`, `PlatformTarget=x64`, MSIX processor architecture `x64`.
- WPF application runs at normal user/medium integrity. `requestedExecutionLevel` is `asInvoker`.

The OS floor is support policy, not a technical limitation of each API. Microsoft currently lists 24H2, 25H2, and 26H1 as serviced Windows 11 lines, with 24H2 Home/Pro support ending in October 2026 ([Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)). Re-evaluate the floor at the first release candidate.

There is no 32-bit requirement. If one appears later, it requires a separate `win-x86` runtime publish and x86 MSIX plus x86 native dependencies and full platform testing. A single “Any CPU” binary is specifically rejected because process/window/capture interop and packaging should be deterministic.

## macOS-to-Windows framework replacements

| Current macOS technology | Windows replacement | Notes |
|---|---|---|
| SwiftUI | WPF XAML, controls, data binding, commands | Port behavior and view hierarchy, not Swift types. |
| AppKit `NSPanel`, `NSWorkspace`, status item | WPF `Window`, HWND/Win32 styles, shell execution, `NotifyIcon` | `HwndSource` is the boundary for messages/styles. |
| CoreGraphics window list/bounds | `EnumWindows`, `GetWindowThreadProcessId`, `DwmGetWindowAttribute`, `SetWindowPos` | No game-memory access. |
| ScreenCaptureKit/CoreGraphics capture | `Windows.Graphics.Capture` secure picker, Direct3D 11 frame pool, `SoftwareBitmap`, JPEG encoder | One player-triggered frame; visible Windows border. |
| AVFoundation + Speech | `Windows.Media.SpeechRecognition.SpeechRecognizer` and microphone privacy controls | Requires package identity and microphone declaration. |
| Security/Keychain | Win32 Credential Manager: `CredWriteW`, `CredReadW`, `CredDeleteW`, `CredFree` | Generic, device-local user credential. |
| ServiceManagement `SMAppService` | MSIX `windows.startupTask` + `StartupTask` | User-controlled and disabled by default. |
| Foundation `URLSession` | one long-lived .NET `HttpClient` | Direct OpenRouter plus explicitly approved external imports. |
| `Codable` / JSONSerialization | `System.Text.Json` | Shared fixtures pin serialization semantics. |
| `SQLite3` C API | `Microsoft.Data.Sqlite` | Bundles SQLite native x64 runtime. |
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
| `Microsoft.Data.Sqlite` | 10.0.10 | SQLite ADO.NET provider and native x64 SQLite | Microsoft; exact transitive native files included in SBOM |
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
- a native capture package: Windows SDK/WinRT plus generated interop is the selected path.

Release CI runs `dotnet list package --vulnerable --include-transitive`, produces an SBOM, and fails if the lock file changes unexpectedly. Dependency updates are separate reviewed changes with unit/package smoke tests.

## Required package manifest surface

The packaged WPF process uses `uap10:TrustLevel="mediumIL"` and `uap10:RuntimeBehavior="packagedClassicApp"`. `windowsApp` is for UWP, not this WPF desktop process; Microsoft classifies Desktop Bridge/packaged desktop applications under `packagedClassicApp` ([packaged desktop runtime behavior](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)).

Required declarations:

- `rescap:Capability Name="runFullTrust"` — required for the normal packaged desktop process. It does not mean administrator elevation.
- `DeviceCapability Name="microphone"` — only for the player-invoked speech button and Windows privacy control.
- `desktop:Extension Category="windows.startupTask"` — disabled by default, with the packaged executable and one stable task ID.

`runFullTrust` is a restricted manifest capability, so the Store submission must explain that it is used for the normal WPF desktop/overlay process and Win32 integrations, not elevation or background service access. Partner Center review of that declaration is a release prerequisite.

Not declared:

- `graphicsCaptureProgrammatic`
- `graphicsCaptureWithoutBorder`
- camera, location, documents/pictures/music libraries
- `privateNetworkClientServer`
- `internetClientServer`
- UIAccess, broad file-system access, packaged service, driver, app capture services

A medium-integrity desktop app already has the current user’s normal outbound network rights, so an AppContainer `internetClient` declaration is not required. Microsoft distinguishes mediumIL/full-trust desktop apps from AppContainer capability grants and still recommends declaring privacy-sensitive device access such as microphone ([app capability declarations](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations)).

## Permission and consent matrix

| Feature | OS declaration | When Windows/player is prompted | Denied/blocked behavior |
|---|---|---|---|
| Overlay/topmost window | None beyond normal desktop execution | No prompt | If enterprise policy blocks the app, it cannot run. |
| BG3 process/window detection | None | No prompt | Show “BG3 not detected” and retain manual overlay/planner access. |
| Direct OpenRouter HTTPS | None for mediumIL | No OS prompt; onboarding explicitly explains network use | Guide stays available; chat shows a precise offline/proxy/provider error. |
| Secure screenshot | No graphics-capture capability because the system picker is used | Picker appears only after “Attach BG3 screenshot”; Windows shows a colored capture border | Cancel/unsupported/minimized/HDR conversion failure leaves chat text-only and stores no image. |
| Microphone/speech | `microphone` device capability; MSIX identity | First mic use can trigger microphone consent; dictation also depends on Online speech recognition | Explain Settings paths and keep text chat fully functional. |
| Start at login | `windows.startupTask`, disabled | Only after the player turns on the setting; Windows may retain final control | Respect `DisabledByUser`; link to Settings > Apps > Startup. |
| OpenRouter key | None | App dialog only, not a Windows permission prompt | Guide works without AI; chat asks for a key. |
| External URLs | None | Default browser/mail app may ask its own questions | Show an open failure; no embedded browser fallback. |

### Screen capture

`GraphicsCapturePicker` is the consent surface. It is initialized with the owner HWND, the user selects the BG3 window, and Windows marks the captured item with its standard border. The session lasts only long enough to get one frame. The app checks `GraphicsCaptureSession.IsSupported()` and keeps `IsBorderRequired=true`. Microsoft’s current capture documentation explicitly describes the secure picker, notification border, Direct3D 11 frame pool, and HDR format/tone-mapping concern ([screen capture](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)).

The optional capture spike must prove:

- DirectX 11 and Vulkan BG3 window selection/capture.
- SDR and Windows HDR, with explicit HDR-to-SDR tone mapping for JPEG.
- minimized, occluded, resized, and closed-window failures.
- 100%, 150%, and 200% DPI on one and multiple monitors.
- overlay exclusion because it is a separate HWND.

No screenshot is written to disk, logged, cached across messages, or captured in the background.

### Microphone and speech

`Windows.Media.SpeechRecognition` requires package identity, which MSIX supplies. A microphone must be present and enabled, the player must grant microphone access, and free-form dictation may require Online speech recognition. Windows lets the player revoke either setting at any time, so every mic start rechecks availability ([speech recognition setup](https://learn.microsoft.com/en-us/windows/apps/develop/input/speech-recognition), [package-identity requirement](https://learn.microsoft.com/en-us/windows/apps/develop/input/manage-issues-with-audio-input)).

Audio is consumed by the Windows speech runtime and is never sent to OpenRouter by this application. The final transcript only populates the unsent chat draft.

When free-form dictation uses Windows Online speech recognition, Microsoft may process the audio under Windows/Microsoft privacy terms. Onboarding and the microphone help text must disclose that distinction from OpenRouter.

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
| Enterprise blocks sideload, capture, mic, speech, or OpenRouter | Detect and explain policy-limited state; guide features remain local. |
| HDR screenshot is washed out | Capture spike and explicit float/HDR-to-SDR conversion path. |
| Speech service/language unavailable | Hide/disable mic with reason; never block typed chat. |
| Credential survives uninstall | Settings Remove key plus README uninstall step. |
| Package update changes schema | transactional migration, pre-migration database copy, rollback test. |
| Native x64 asset omitted | clean-VM install/package-content test and x64-only CI assertion. |
| 32-bit/ARM request appears | Treat as a separately estimated port; do not relabel x64 output. |

## Permission acceptance gate

The Windows build cannot leave platform validation until:

- the manifest contains only the declared minimum surface;
- a clean x64 Windows 11 VM can install and run without admin or developer mode;
- capture and mic prompts happen only after their buttons are pressed;
- denying every optional permission leaves runs/routes/party/builds/gear/acts usable;
- outbound chat works with no inbound firewall rule or local listener;
- Credential Manager contains the key while SQLite/logs/package do not;
- process-monitor evidence shows no BG3 file, memory, save, or injection access;
- signed package/publisher verification passes.
