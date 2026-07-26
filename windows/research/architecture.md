# Windows Architecture Recommendation

Status: active Windows MVP architecture

Decision date: 2026-07-25

## Decision

Use a **C# WPF desktop application on .NET 10 LTS**, targeting Windows 11 x86-64, with narrow Win32 and Windows Runtime adapters. Publish it as a self-contained x64 MSIX. Keep route/build/gear logic, SQLite persistence, bundled data, Windows integration, and direct OpenRouter calls in one process.

This is both the simplest and the best production-capable option. WPF is actively supported in .NET, gives direct control of a transparent topmost HWND, and avoids a browser UI or separately deployed application runtime. .NET 10 is active LTS through November 2028 ([.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)); WPF is a Windows-only .NET UI framework with XAML, controls, binding, graphics, and animation ([WPF overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)).

The project targets `net10.0-windows10.0.26100.0`, `RuntimeIdentifier=win-x64`, and `PlatformTarget=x64`. The supported launch baseline is Windows 11 24H2 (build 26100) or later; before the real release, bump the floor if 24H2 Home/Pro is no longer serviced. Microsoft’s current Windows 11 release table is the source for that decision ([Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)).

## Options considered

### Option A — WPF + Win32/WinRT in one process (recommended)

```text
 [Tray + WPF overlay/planner]
              |
        [App coordinator]
        /       |        \
 [Domain] [Platform] [OpenRouter HTTPS]
    |        |             |
 [SQLite] [Win32/WinRT]  openrouter.ai
    |
 [Bundled guide + media]
```

Advantages:

- Direct HWND control for no-activate, topmost, transparent overlay behavior.
- Mature XAML/data binding maps cleanly from SwiftUI without porting AppKit architecture.
- Built-in .NET networking, JSON, images, threading, and test tooling.
- Self-contained MSIX needs no player-installed .NET, Node, Python, or model runtime.
- Windows SDK APIs are callable from .NET using a Windows-specific target framework; a Windows App SDK dependency is not required for the core plan ([WinRT from desktop apps](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps)).

Costs:

- Some low-level APIs require generated P/Invoke/COM bindings.
- WPF visual styling must be intentionally matched to the macOS overlay.
- Screenshot/capture and microphone/speech adapters are intentionally absent from the Windows MVP.

### Option B — WinUI 3 + Windows App SDK

```text
 [WinUI 3 overlay/planner]
              |
 [Windows App SDK runtime/deployment]
              |
 [Domain + SQLite + OpenRouter + Win32 interop]
```

Advantages:

- Newer Fluent controls and first-party Windows App SDK templates.
- Convenient modern Windows lifecycle and interop helpers.

Costs:

- Transparent, nonactivating overlay behavior still drops to HWND/Win32 interop.
- Adds Windows App SDK deployment/versioning surface and a larger package.
- Rewrites a dense product UI onto a newer framework without removing the hard platform work.

Use only if the overlay spike finds a WPF rendering defect that cannot be resolved without changing product behavior. Microsoft positions Windows App SDK as an optional modernization layer that also supports WPF; it is not required for ordinary Windows SDK APIs ([Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/)).

### Option C — Tauri/Rust host + WebView2 UI

```text
 [HTML/CSS in WebView2]
          |
     IPC bridge
          |
 [Rust host: HWND/SQLite/OpenRouter]
```

Advantages:

- Familiar web layout and compact Rust native host.
- Potentially easy CSS iteration.

Costs:

- Two UI/runtime worlds and an IPC bridge for every action/state update.
- WebView2 focus, transparency, accessibility, capture, and GPU behavior become extra overlay variables.
- Duplicates serialization/state boundaries without product benefit.
- Requires another dependency and security update surface.

Reject for the first Windows port.

## Visible platform adaptations

The main surface hierarchy stays the same. Three Windows-specific changes are visible:

```text
 Tray
 ├─ Show Overlay / Planner / Map / Runs / Launch BG3
 ├─ Hide Pet / Settings
 └─ Quit

 Expanded overlay
 ├─ Now | Route | Party | Loadout | Act
 ├─ Chat
 │  ├─ Scope: Current | Route | Party
 │  └─ Typed draft / Send / Sources
 └─ Settings
    └─ AI: OpenRouter key status / Test / Remove / fixed release model
       (no provider picker, Ollama, or local-model controls)
```

The overlay keeps the same compact/expanded card hierarchy. Windows high contrast, text scaling, reduced animation, and keyboard focus may replace translucency or motion; that is an accessibility adaptation, not a new product layout.

## Component boundaries

Keep four production projects and two test projects. Do not recreate the macOS global `AppState` as a single dependency hub.

```text
 BG3HonorAssistant.App
   WPF windows, tray, view models, navigation, composition root
                 |
 BG3HonorAssistant.Core
   run/route/party/build/gear/act models and pure decisions
          |                         |
 BG3HonorAssistant.Infrastructure   BG3HonorAssistant.Windows
 SQLite, resources, OpenRouter,     HWND, process/window,
 import parsing                     credentials, startup
```

Responsibilities:

- **App:** WPF views, view models, commands, dialogs, tray menu, and app lifetime. It owns no SQL, HTTP, or P/Invoke.
- **Core:** immutable/serializable models and deterministic operations for current goal, route ledger, readiness, run creation, party rules, build validation, gear ownership, and act locking.
- **Infrastructure:** `RunRepository`, schema migrations, resource loader, `OpenRouterClient`, import fetch/parser, diagnostics redaction.
- **Windows:** `OverlayWindowService`, `Bg3WindowLocator`, `GameLauncher`, `CredentialStore`, `StartupTaskService`, `SingleInstanceService`, `ShellLinkService`. No capture or speech service is part of the shipped graph.

Use constructor injection in the composition root, but no dependency-injection framework initially. The graph is small enough to construct directly and tests can pass fakes.

## Core data flow

### Route and state

```text
 user command
      |
  Core reducer/service ---- reads ----> bundled guide
      |
 new HonorRun snapshot
      |
 SQLite transaction -> revision -> UI notification
```

The UI calls one application command at a time. The command validates preconditions, calculates a new run snapshot, stores current state plus its bounded revision transactionally, and then publishes the committed state. Reads never depend on a second process. SQLite remains the persistence engine because it already carries the macOS snapshot model and Microsoft provides a lightweight first-party .NET provider ([Microsoft.Data.Sqlite](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/)).

### Direct OpenRouter chat

```text
 typed chat draft + selected scope
                         |
              prompt/context builder
                         |
                  HttpClient POST
                         |
          https://openrouter.ai/api/v1/chat/completions
                         |
         validated response -> session-only chat UI
```

Rules:

- Read the Bearer key from Credential Manager immediately before a request.
- Send only the selected bundled guide context, recent session history, and user text.
- Use `System.Text.Json`; do not ship an OpenAI/OpenRouter SDK.
- One timeout/cancellation policy, bounded response size, and explicit HTTP/provider errors.
- No deterministic chat fallback, proxy, telemetry service, or hidden retry to another model.
- Default model is `google/gemini-3.6-flash` as verified on 2026-07-25; one release constant controls it, and release CI rechecks text and structured-output capabilities against OpenRouter’s models endpoint ([OpenRouter quickstart](https://openrouter.ai/docs/quickstart), [current model](https://openrouter.ai/google/gemini-3.6-flash)).

### Overlay lifecycle

```text
 BG3 process/window events ---> Bg3WindowLocator
                                  |
 user visibility setting ------> Overlay policy
                                  |
 current route/run state ------> WPF overlay HWND
                                  |
                      SetWindowPos / DPI / bounds
```

`Bg3WindowLocator` matches only the documented `bg3.exe`/`bg3_dx11.exe` processes and their owned visible top-level window. Use `QueryFullProcessImageNameW` for path/name verification with limited query rights, `EnumWindows` plus `GetWindowThreadProcessId`, and `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` for visual bounds ([QueryFullProcessImageNameW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew), [EnumWindows](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumwindows), [DwmGetWindowAttribute](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmgetwindowattribute)).

Use `SetWinEventHook` with `WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS` for foreground/location changes and a two-second poll only to recover missed events. The out-of-context callback keeps hook code in the assistant process. Never open BG3 for memory access, inject a DLL, install a driver, read saves, or require administrator rights.

The WPF window starts with `WindowStyle=None`, `AllowsTransparency=true`, `Topmost=true`, and `ShowInTaskbar=false`. On source initialization, apply:

- `WS_EX_TOOLWINDOW` to keep the overlay out of Alt+Tab/taskbar.
- `WS_EX_NOACTIVATE` while passive.
- `SetWindowPos(HWND_TOPMOST, ...)` after a bounds change.
- Per-monitor-v2 DPI awareness and `WM_DPICHANGED` handling.

When the player clicks a text box, deliberately activate the overlay and restore passive behavior after editing. Do not use keyboard/mouse hooks.

### Approved Windows MVP exclusions

Screenshot capture, image attachments, clipboard-image ingestion, microphone access, speech recognition, and dictation are not implemented. No related WPF controls, Windows adapters, package capabilities, dependencies, or OpenRouter image payloads may ship. Historical feasibility notes belong only in non-shipping research history and are not part of this architecture.

## Persistence and ownership

MSIX LocalState contains:

```text
 LocalState/
   state.sqlite3
   state.sqlite3-wal
   state.sqlite3-shm
   logs/                 # rotating diagnostics, no prompts/keys/images
```

SQLite tables:

- `schema_migrations(version, applied_at)`
- `runs(id, name, guide_version, snapshot_json, created_at, updated_at)`
- `run_revisions(id, run_id, revision, snapshot_json, created_at)`
- `settings(key, value_json)`
- `imported_builds(id, name, build_json, created_at, updated_at)`

Keep the full `HonorRun` snapshot JSON to minimize behavioral drift, while indexes/settings/imported builds get first-class rows. Enable WAL, foreign keys, busy timeout, and a maximum of 20 revisions per run. Make a timestamped pre-migration database copy before destructive schema changes.

Credential Manager exclusively owns the OpenRouter key. `CredWriteW` writes a generic credential target `BG3HonorAssistant/OpenRouter` with `CRED_PERSIST_LOCAL_MACHINE`; `CredReadW` reads it for one request; `CredDeleteW` supports Settings > Remove key. The API operates on the current user’s credential set ([CredWriteW](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew), [CredReadW](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw)).

## Dependency policy

Runtime packages are deliberately few:

- `Microsoft.Data.Sqlite` for SQLite.
- `AngleSharp` for HTML-to-text during reviewed-build imports.
- `PdfPig` for PDF-to-text during reviewed-build imports.

Use the .NET Windows target framework and generated `LibraryImport`/Microsoft CsWin32 bindings for the narrow Win32 surface. CsWin32 is a build-time source generator and adds no large runtime assembly ([Microsoft CsWin32](https://github.com/microsoft/CsWin32)). Avoid CommunityToolkit, MVVM frameworks, HTTP SDKs, embedded browsers, and capture/speech libraries.

Pin all NuGet versions through central package management and a committed lock file. Produce an SBOM and update `THIRD_PARTY_NOTICES.md` in release CI. AngleSharp is MIT and .NET Foundation supported; PdfPig is Apache-2.0 ([AngleSharp](https://github.com/AngleSharp/AngleSharp), [PdfPig](https://github.com/UglyToad/PdfPig)).

## Resolved architecture assumptions

- A separately installed server is **not required**. All work is in one desktop process.
- A player-installed .NET runtime is **not required**. The publish is self-contained.
- Windows App SDK/WinUI is **not required** for WPF or the selected Win32/WinRT APIs.
- Screen capture, image attachment/clipboard ingestion, microphone access, speech recognition, and dictation are approved exclusions and must be absent from shipped bytes.
- Outbound OpenRouter HTTPS needs no inbound listener or Windows Firewall rule.
- True exclusive full-screen is not a supported overlay mode; BG3 Windowed/Borderless Windowed is.
- The assistant never requires administrator, UIAccess, game injection, save access, or a BG3 mod.
- There is no 32-bit x86 deliverable in this scope.

The remaining spikes in `implementation-plan.md` verify hardware behavior; they do not choose an unresolved architecture.
