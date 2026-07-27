# Windows Feature-Parity Matrix

Status: implementation plan, not a shipping Windows build

Audit date: 2026-07-25

## Scope and interpretation

`/mac` is the behavioral source of truth. The audit covered the live Swift entry point, overlay controller, all feature views and `AppState` extensions, persistence and platform services, packaged resources, tests, CI, and macOS release scripts. Top-level documentation was used only as supporting context because parts of it describe older runtime behavior.

The Windows product supports exactly native ARM64 (`arm64`/`win-arm64`) and x64/AMD64 (`x64`/`win-x64`) with separate self-contained MSIX packages. It does not support 32-bit x86, neutral/AnyCPU native packaging, or Arm64EC.

Audit cautions:

- `SECURITY.md` and parts of the current install/release prose describe older hosted/keyless or source-build behavior. They are not evidence of the live Swift runtime.
- Legacy backend client/process/authentication types still compile, but no live `AppState` path starts them.
- Current macOS release code can manage Ollama/local models, which this Windows product explicitly excludes.
- Current chat source can synthesize a deterministic answer on provider failure. Windows intentionally corrects that to a real OpenRouter response or explicit failure.
- Act 2 contains build/gear data but no route checkpoints, walkthrough, or timed-event data in guide `2026-07-18-all-act-review-v2`.

Legend:

- **Equivalent** — preserve behavior with the named Windows API or component.
- **Adaptation** — preserve user value but change platform behavior deliberately.
- **Exclusion** — do not port; the reason and effect are explicit.
- **Data gap** — current macOS bundle does not provide the feature data, so Windows cannot invent it.

## Application shell, game detection, and overlay

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| O-01 | Menu-bar app with Show Overlay, Planner, Map, run switcher, Launch BG3, pet toggle, Settings, and Quit (`BG3AssistantApp.swift`). | WPF app plus a `System.Windows.Forms.NotifyIcon` tray menu with the same commands. Keep a normal Settings/Planner window available from the taskbar when open. | Equivalent |
| O-02 | One process per user, enforced by an Application Support lock file; a second launch activates the first (`SingleInstanceGuard.swift`). | Per-user named mutex plus a registered window message to activate the existing instance. No localhost listener or Windows service. | Equivalent |
| O-03 | Launches Steam app 1086940 through `steam://run/1086940`. | `Process.Start(new ProcessStartInfo("steam://run/1086940") { UseShellExecute = true })`; if Steam is unavailable, show a clear error and let GOG players launch normally. | Equivalent |
| O-04 | Detects BG3 from visible windows and running apps, polling every two seconds (`BG3Detector.swift`). | Match `bg3.exe` (Vulkan) and `bg3_dx11.exe` (DirectX 11), then use `EnumWindows`, `GetWindowThreadProcessId`, visibility/ownership checks, and the largest valid top-level window. Larian documents both executable names ([Larian support](https://larian.com/support/baldur-s-gate-3?query=3.)). Poll every two seconds as a recovery path and use `SetWinEventHook` for foreground/location changes. Never inspect game memory or files. | Equivalent |
| O-05 | Overlay appears automatically when BG3 is detected and the guide is ready, subject to a user setting; first-run onboarding can force it visible. | Same state rule. Game detection only decides visibility and positioning; it never injects into BG3. | Equivalent |
| O-06 | Borderless, transparent, always-on-top, nonactivating `NSPanel` across Spaces/full-screen, with text fields allowed to activate (`OverlayPanelController.swift`). | WPF `WindowStyle=None`, `AllowsTransparency=true`, transparent background, `Topmost=true`; apply `WS_EX_TOOLWINDOW`, `WS_EX_TOPMOST`, and passive `WS_EX_NOACTIVATE` through the HWND. Temporarily permit activation for text input and dialogs. WPF supports transparent/topmost windows, while Win32 extended styles provide no-activate/tool-window semantics ([WPF windows](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/), [extended window styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)). | Equivalent |
| O-07 | Overlay can sit over macOS full-screen BG3. | Support BG3 in **Windowed** or **Borderless Windowed** mode. A normal overlay is not guaranteed above true exclusive full-screen content, and the assistant will not inject a graphics hook. Microsoft recommends the flip model for windowed/borderless presentation and documents composition/direct-flip behavior ([DXGI flip model](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model)). | Adaptation |
| O-08 | Overlay avoids the bottom hotbar and upper-right minimap, defaults to the right edge, and follows/resizes with the game window (`OverlayMetrics.swift`, `AppState+Overlay.swift`). | Reuse the current normalized geometry rules against `DWMWA_EXTENDED_FRAME_BOUNDS`; reposition with `SetWindowPos`. Recalculate on WinEvent location changes and `WM_DPICHANGED`. | Equivalent |
| O-09 | Position is draggable and stored as a normalized anchor, clamped to BG3 or the primary display. | Drag the WPF surface through `DragMove`; persist normalized anchor in SQLite settings and clamp per monitor work area. | Equivalent |
| O-10 | Expanded window size changes by tab and onboarding state. | Preserve the same per-surface size table in device-independent WPF units, then clamp to the current monitor’s work area. | Equivalent |
| O-11 | Collapsed densities: minimal pet, focus card, and reference view. | Preserve all three density modes and the same setting. | Equivalent |
| O-12 | Minimal mode is an animated twilight pet; player can hide/show it (`PetSpriteView.swift`, `PetAnimationModel.swift`). | Port the deterministic animation state machine and bundle `twilight-cleric.webp`; render with WPF image frames/animations. | Equivalent |
| O-13 | Focus mode shows the current action, level, danger/avoid text, Route/Ask/Task done shortcuts, and a context menu for snooze, mute, pin, and density. | Preserve the controls and action ownership exactly. | Equivalent |
| O-14 | Expanded primary tabs are Now, Route, Party, Loadout, and Act, with separate Chat and Settings actions (`OverlayView.swift`). | Preserve hierarchy and labels; use WPF navigation/content controls, not a web view. | Equivalent |
| O-15 | No system-wide global hotkey exists in the current macOS source. | Do not invent a default hotkey. Tray/menu commands are parity. If a later user-configurable hotkey is approved, use `RegisterHotKey`/`UnregisterHotKey`, report collisions, and avoid reserved Windows/F12 combinations ([RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)). | Exclusion: nonexistent source feature |
| O-16 | Overlay is interactive within its window; it is not a whole-screen click-through layer. | Keep hit testing only inside the compact overlay bounds. Do not add global mouse hooks or raw-input capture. | Equivalent |
| O-17 | Overlay hides or reports degraded state when BG3/guide/provider conditions fail. | Preserve explicit diagnostics and manual Show Overlay. If BG3 is run elevated, tell the player to run it normally; the assistant must not request elevation to follow it. | Equivalent |
| O-18 | The overlay uses a consistent dark glass style, rounded cards, color-coded danger/readiness, icons, and restrained animation (`AssistantGlassStyle.swift`, card views). | Recreate the hierarchy and semantic colors in WPF resources. Respect Windows high contrast and reduced-animation preferences; those accessibility adaptations take precedence over translucency. | Equivalent with accessibility adaptation |

## Runs, route, walkthrough, and current guidance

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| R-01 | Multiple named independent runs; create, rename, switch, and restore active run (`RunStore.swift`, Settings). | Preserve with SQLite `runs`, `run_revisions`, and `settings` tables. | Equivalent |
| R-02 | New run can use the default party or reuse current characters/build presets while resetting levels, story, route, gear, and act state. | Port the same pure creation rules and tests. | Equivalent |
| R-03 | Up to 20 JSON revisions per run support recovery. | Keep 20 transactional snapshots per run. Add no cloud sync in this port. | Equivalent |
| R-04 | A guide-version mismatch archives the existing run and starts a fresh compatible run while preserving reusable party/build presets. | Preserve the migration gate and show the same explanation before switching active state. | Equivalent |
| R-05 | Now selects the next route step, a gear target, a pinned fight, route completion, or an unavailable/later-act state (`AppState+Goal.swift`, `NowTabView.swift`). | Port the priority function as domain code and cover every state with unit tests. | Equivalent |
| R-06 | Current guidance includes action, why, avoid, reward, readiness, blockers, warnings, preparation, decisions/outcomes, incident protocol, risk/reward, and sources. | Preserve all fields and disclosure hierarchy. | Equivalent |
| R-07 | Route groups steps by phase, shows progress, and filters All/Core/Equipment. | Preserve filters, phase groups, progress calculation, and equipment pickup integration. | Equivalent |
| R-08 | Spoiler policy supports full-act or “next three,” with lockout/deadline warnings. | Preserve both policies and warning semantics. | Equivalent |
| R-09 | Steps can be pending/current/later/completed/skipped/caught-up/revisit; archived groups remain inspectable. | Preserve the full ledger. No state may be silently collapsed into “done.” | Equivalent |
| R-10 | Step detail exposes prerequisites, completion checks, choices/outcomes, sources, incident/risk data, gear, and focus controls (`StepDetailView.swift`). | Preserve the detailed sheet/page and deep links from Now/Route. | Equivalent |
| R-11 | Complete, skip, revisit, catch-up, “Task done,” and undo-sensitive actions update run state. Irreversible guidance requires confirmation. | Preserve state transitions and confirmation gates; map destructive confirmations to standard WPF dialogs. | Equivalent |
| R-12 | Fight checkpoints can be pinned, snoozed for ten minutes, or muted. | Preserve transient snooze plus persisted pin/mute state. Use an in-process timer; no scheduled task or background service. | Equivalent |
| R-13 | Gear targets temporarily override the Now goal, with path/acquisition text, Got it, clear, and map actions (`AppState+GearTarget.swift`). | Preserve target priority and controls. | Equivalent |
| R-14 | External map links open in the default browser; there is no shipping local map backend. | Open the existing MapGenie/external URLs with the Windows shell. Do not add a bundled web server. | Equivalent |
| R-15 | Act 1 and Act 3 contain route data; the current guide bundle has zero Act 2 checkpoints/walkthrough/timed events. | Display “Act 2 route is not available in this guide version” while keeping Act 2 builds/gear. This is a content gap, not a Windows omission. Act 2→3 transition remains blocked by the same route gate until shared data changes. | Data gap |

## Party, reviewed builds, manual builds, gear, and acts

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| P-01 | Party roster supports active, camp, unrecruited, dead, and departed states; active party max is four, and solo is allowed (`PartyTabView.swift`). | Preserve states, max-four invariant, swaps, and solo play. | Equivalent |
| P-02 | Eleven companion portraits plus Dark Urge/custom identity cues are bundled. | Reuse the same licensed repository assets in the Windows package. | Equivalent |
| P-03 | Withers hirelings can be added (maximum three) and only inactive hirelings can be removed. | Preserve rules and confirmations. | Equivalent |
| P-04 | Per-member editing includes name, level 1–12, class/build, roster status, respec/reset, and undo last party change. | Preserve fields and undo transaction. | Equivalent |
| P-05 | Reviewed builds show level guidance, class/subclass/choices, tactics, next step, and comparisons before assignment. | Parse the same reviewed-build payload and preserve comparison/assignment UI. | Equivalent |
| P-06 | Build import accepts HTTPS URL, plain text, or PDF up to 5 MB/60,000 extracted characters, then asks the configured model for a structured build. | Preserve limits. Use `HttpClient`, AngleSharp for HTML, and PdfPig for PDF text. Disable automatic redirects; resolve and reject loopback/private/reserved addresses on every hop; allow only HTTPS and standard port 443. The stricter redirect/DNS handling corrects a source/documentation gap. | Adaptation: production-safe fetch |
| P-07 | Imported builds validate 27-point buy, distinct +2/+1, levels, and level-12 class split, are marked “verify,” persist globally, and can replace an assigned build after confirmation. | Port validators and tests; store imported builds in SQLite rather than a separate JSON file. | Equivalent behavior, adapted storage |
| P-08 | Manual planner covers level 1–12, all 12 classes, multiclassing, subclasses, feats, spells, class options, icons, and the generated spell catalog (`ManualBuild.swift`, `ManualBuildPlannerView.swift`). | Port the catalog-driven planner and bundle all option icons/spell data. | Equivalent |
| P-09 | Explorer mode disables multiclassing, though current onboarding does not allow Explorer to finish into the overlay. | Preserve the rule for model correctness and preserve the onboarding block. | Equivalent |
| P-10 | Ability recipes enforce exact point buy, +2/+1, final scores, setup-applied state, source breakdowns, and unique-across-party bonuses (`AbilityProgression.swift`). | Port the calculation engine and fixtures before UI work. | Equivalent |
| P-11 | Loadout has active-party paper dolls with helmet, amulet, cloak, two rings, armor, gloves, main/off hand, boots, instrument, and ranged slots (`LoadoutTabView.swift`, `LoadoutSlot.swift`). | Preserve every slot and active-party switcher. | Equivalent |
| P-12 | Gear cards include icons, effects, acquisition, requirements, wiki/map, region/rarity, and act. | Preserve all metadata and external links. | Equivalent |
| P-13 | Player can mark equipped/unequipped, choose an owner, target an item, swap a build slot to a catalog alternative, and revert. | Preserve override precedence and persisted ownership/review state. | Equivalent |
| P-14 | Conflicts resolve by manual override, then earliest build assignment, then deterministic name order; UI offers “Give to member.” | Port the same deterministic algorithm and existing gear tests. | Equivalent |
| P-15 | Route pickups show relevant unowned/current/claimed items and retain unmatched “other pickups.” | Preserve integration; no item is silently discarded. | Equivalent |
| P-16 | Act ledger browses Acts 1–3 as active, preview, or locked history (`ActTabView.swift`, `AppState+Acts.swift`). | Preserve all ledger modes. | Equivalent |
| P-17 | Advancing requires every planned gear item reviewed obtained/missed plus explicit acceptance of route consequences. | Preserve gates and immutable transition record with gear snapshot/unresolved route count. | Equivalent |
| P-18 | Act 3 finalization locks the run; prior acts are immutable. | Preserve lock semantics and tests. | Equivalent |

## Typed Chat, OpenRouter, and approved Windows MVP exclusions

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| A-01 | Current macOS source supports multiple provider choices, including Ollama/local models and direct OpenRouter (`AIProvider.swift`). | Windows exposes **OpenRouter only**. Remove Ollama, Gemma/Qwen, local model discovery, model downloads, runtime status, and provider switching. Guide tabs remain usable without a key. | Exclusion: explicit product requirement |
| A-02 | Direct OpenRouter posts to `/api/v1/chat/completions` with Bearer key and optional attribution headers (`AssistantAIClient.swift`). | Use one typed `HttpClient` in-process. No SDK, proxy, backend, localhost port, or service. OpenRouter documents the direct HTTPS request format ([quickstart](https://openrouter.ai/docs/quickstart)). | Equivalent |
| A-03 | macOS currently names `google/gemini-3-flash-preview`. | Initial Windows default: `google/gemini-3.6-flash`, verified through OpenRouter’s public model catalog on 2026-07-25 for typed text and structured outputs. Keep it in one release configuration constant and validate those capabilities in CI before every release; do not silently switch models at runtime ([model page](https://openrouter.ai/google/gemini-3.6-flash)). | Adaptation: current model |
| A-04 | Chat grounds answers with current step/route/party context, recent history, bundled source metadata, quick prompts, and scope selection. | Preserve typed prompt construction, current/route/party scopes, quick prompts, source display, Markdown, and links. Image input/rendering is outside the Windows MVP. | Equivalent for typed chat |
| A-05 | Chat conversation is in memory only; run state is persisted separately. | Keep history session-only. “Clear chat” clears memory; app exit removes it. | Equivalent |
| A-06 | Current source can return a deterministic guide answer when OpenRouter fails, conflicting with the intended real-provider-only behavior (`AppState+Chat.swift`). | Show explicit authentication/rate-limit/network/model errors and retry. Never present bundled fallback prose as a model answer. Bundled tabs remain available independently. | Adaptation: defect correction |
| A-07 | Opening chat may automatically prepare a one-window screenshot; user can preview, retake, remove, and send it only with the next prompt (`AppState+Capture.swift`). | Do not port screenshot or image attachment UI, clipboard-image ingestion, capture permissions, capture services, or image requests. Product and package tests must keep them absent from delivered bytes. | Approved Windows MVP exclusion |
| A-08 | Screenshot is JPEG, bounded to the BG3 window, and the overlay is not included. | Do not capture, convert, encode, persist, or upload frames or screenshots in the Windows MVP. | Approved Windows MVP exclusion |
| A-09 | Speech button requests speech/microphone permission on use, supplies partial transcript, and writes the final transcript into chat draft (`SpeechInputService.swift`). | Do not port microphone access, speech recognition, dictation, related UI, services, or package capabilities. Typed chat remains available. | Approved Windows MVP exclusion |
| A-10 | Chat is unavailable where route data is unavailable. | Preserve the current route-availability gate unless shared product behavior changes first. | Equivalent |

## Onboarding, settings, startup, privacy, and diagnostics

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| S-01 | Versioned onboarding supports fresh and mid-run setup (`OnboardingView.swift`, `Onboarding.swift`). | Preserve versioned wizard, replay tour, and resume-on-incomplete behavior. | Equivalent |
| S-02 | Difficulty choices include Balanced, Tactician, and Honour; Explorer explains that the overlay is unsupported and closes. Custom exists in the model but is not offered. | Preserve the exact offered choices and Explorer explanation; do not expose Custom. | Equivalent |
| S-03 | Player selects full-act or next-three spoiler policy. | Preserve. | Equivalent |
| S-04 | Mid-run setup selects act and last landmark, then marks prior steps caught up. | Preserve catch-up calculation. | Equivalent |
| S-05 | Party member status/level setup is part of onboarding. | Preserve. | Equivalent |
| S-06 | Provider selection includes local and OpenRouter options on macOS. | Replace with: “Use guide without AI,” or “Add OpenRouter key.” No other provider/runtime choices appear. | Adaptation |
| S-07 | Ready screen explains local/offline behavior and offers launch at login, applied only after completion. | Explain that guide/run data is local but OpenRouter chat and external links use the internet. Keep startup opt-in and apply it only after onboarding finishes. | Adaptation |
| S-08 | Settings include overlay while BG3 runs, startup, density, tour, runs, difficulty, spoilers, provider/key/model, bug report, legal/notices, and diagnostics. | Preserve all applicable controls. Replace provider/model controls with OpenRouter key status, Remove key, connection test, and the release-selected model label. | Adaptation |
| S-09 | Login item uses `SMAppService` and remains user-controlled (`LoginItem.swift`). | Declare an MSIX `windows.startupTask`, then call `StartupTask.RequestEnableAsync` only from the toggle. Respect `DisabledByUser`; direct the player to Settings > Apps > Startup when Windows owns the decision ([StartupTask](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask?view=winrt-26100)). | Equivalent |
| S-10 | Diagnostics expose BG3, guide, provider/AI, and error state. | Preserve plus Windows package version, OS build, process/window match, and signing channel. Never include the API key, prompt, or chat content. | Equivalent |
| S-11 | Bug report opens an email link; legal links and third-party notices are bundled. | Preserve with the default mail client/browser and bundled notices. | Equivalent |

## Persistence, credentials, services, assets, tests, and releases

| ID | macOS behavior and source | Windows decision | Disposition |
|---|---|---|---|
| I-01 | Run snapshots/settings use SQLite in Application Support with WAL/full mutex (`RunStore.swift`). | Use `Microsoft.Data.Sqlite` in MSIX LocalState, WAL mode, transactions, foreign keys, and schema migrations. One process means no cross-process run polling. | Equivalent behavior, simpler lifecycle |
| I-02 | Imported builds use `imported-builds.json`. | Move imported builds into the same SQLite database to avoid a second persistence protocol; preserve reusable/global behavior. | Adaptation |
| I-03 | Overlay anchor/settings use `UserDefaults`; snooze, active dialogs, undo UI, and chat are transient. | Store durable settings in SQLite and preserve the same transient boundaries. | Equivalent |
| I-04 | OpenRouter keys use macOS Keychain generic passwords, device-local after first unlock (`CredentialStore.swift`). | Win32 Credential Manager generic credential through `CredWriteW`, `CredReadW`, and `CredDeleteW`, target `BG3HonorAssistant/OpenRouter`, with `CRED_PERSIST_LOCAL_MACHINE` so it remains local to this computer/user ([credential persistence](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw), [CredReadW](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw)). Never place the key in SQLite, logs, diagnostics, crash reports, or the package. | Equivalent |
| I-05 | `BackendProcessManager`, `BackendClient`, endpoint/authenticator models, and tests remain compiled but no live `AppState` path starts them. | Do not port dead backend lifecycle or legacy backend tests. Record this exclusion in the repository migration notes. | Exclusion: unreachable legacy code |
| I-06 | macOS release can bundle Ollama and a local model runtime. | Do not package Ollama, model files, installers, daemons, or model-management UI. | Exclusion: explicit requirement |
| I-07 | Python scripts compile/validate source data into committed `guide-bundle.json`; Python is not needed for the live Swift UI. | Reuse the existing generated JSON and asset pipeline at build time. Release output contains data only, never Python or a Python environment. | Equivalent |
| I-08 | Bundle contains the guide, app/pet artwork, 11 companion portraits, 51 item icons, 697 build-option icons, generated spell catalog, privacy manifest, and notices. | Include the guide and all media in the MSIX read-only install tree; generate a Windows privacy notice and retain third-party notices. Validate counts/hashes in CI. | Equivalent |
| I-09 | External map/wiki/legal URLs leave the app. | Preserve shell-open behavior and show domains before opening where the current UI already does. | Equivalent |
| I-10 | Swift tests cover run safety, onboarding, run creation, act locks, manual builds/assets, imports, and gear; legacy backend endpoint tests also exist. | Port domain tests to xUnit first; omit only the unreachable-backend tests. Add Windows platform contract tests for credentials, SQLite, manifest, package contents, detection, positioning, startup, and absence of the approved screenshot/microphone features. | Equivalent plus required Windows coverage |
| I-11 | macOS validation builds/tests Swift, validates a no-signing app, and also runs Python backend tests on Linux (`scripts/macos/validate.sh`, `.github/workflows/ci.yml`). | Add explicit Windows ARM64 and x64 CI jobs: locked restore, build, execute xUnit on matching test-host ISA, publish, package, recursively inspect, and retain evidence. Existing macOS CI remains unchanged. | Equivalent |
| I-12 | macOS release scripts build/sign/notarize ZIP/TestFlight artifacts and currently have a source-build install path. | Produce separate self-contained ARM64 and x64 MSIX packages; validate each before any bundle. Prefer Microsoft Store for stable distribution and a signed HTTPS App Installer feed for beta. | Adaptation |
| I-13 | macOS permissions include screen recording, microphone/speech, login item, keychain, and outbound HTTPS. | Windows requests no screen-capture, microphone, or speech capability. It uses only the user-controlled startup task, Credential Manager, and outbound HTTPS. No admin, accessibility/UIAccess, driver, inbound listener, private-network, game-file, process-injection, or save access. | Adaptation with approved MVP exclusions |
| I-14 | macOS release uses Apple signing/notarization/Gatekeeper. | Use Store signing for the stable MSIX or sign/timestamp the direct beta MSIX with Artifact Signing/OV under a stable publisher identity. Expect early non-Store SmartScreen reputation prompts even when signed ([SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation), [MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)). | Equivalent platform control |

## Parity gate

Windows feature parity is complete only when every Equivalent/Adaptation row has an acceptance result, every Exclusion remains intentional, and the Act 2 data gap is visible. Native ARM64 exact-name hosts and the packaged ARM64 product must pass physical Windows 11 ARM64 QA; x64 tests must execute in x64 Windows CI and separately smoke-test under ARM64 emulation. Neither is native-x64 physical hardware proof, which remains an explicit release gate.
