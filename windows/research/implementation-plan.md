# Windows Implementation Plan

Status: ready for a follow-up build goal

Estimate basis: one experienced Windows/.NET engineer, current `/mac` source and resources, 2026-07-25

## Guardrails

- Preserve `/mac`; it remains the behavioral oracle throughout the port.
- Windows 11 x86-64/AMD64 only. Do not use “x86” on artifacts because players commonly read it as 32-bit.
- Overlay only: no BG3 mod, plugin, injection, save editing, process memory, game-file access, driver, or administrator requirement.
- OpenRouter direct from the desktop process. No Ollama, local model, AI runtime, Python/Node runtime, server, proxy, or localhost listener.
- Production output is one self-contained x64 MSIX install action.
- Screenshot capture, clipboard-image ingestion, microphone access, speech recognition, and dictation are approved Windows MVP exclusions. They must have no shipped UI, service, or package capability.
- Every parity row in `feature-parity.md` needs evidence before release.

## Proposed `/windows` structure

```text
 windows/
   README.md
   BG3HonorAssistant.slnx
   Directory.Build.props
   Directory.Packages.props
   global.json

   src/
     BG3HonorAssistant.Core/
       Models/
       Runs/
       Route/
       Party/
       Builds/
       Gear/
       Acts/
     BG3HonorAssistant.Infrastructure/
       Persistence/
       Resources/
       OpenRouter/
       BuildImport/
       Diagnostics/
     BG3HonorAssistant.Windows/
       Overlay/
       GameDetection/
       Credentials/
       Startup/
       Shell/
       SingleInstance/
     BG3HonorAssistant.App/
       App.xaml
       Views/
       ViewModels/
       Commands/
       CompositionRoot.cs

   tests/
     BG3HonorAssistant.Core.Tests/
     BG3HonorAssistant.Infrastructure.Tests/
     BG3HonorAssistant.Windows.Tests/
     BG3HonorAssistant.Package.Tests/

   package/
     Package.appxmanifest
     BG3HonorAssistant.appinstaller.template
     Store/
     Assets/

   Resources/
     Data/
       spell-catalog.json
     Windows/
       app-icon assets

   tools/
     build-release.ps1
     verify-package.ps1
     generate-spell-catalog.py
     compare-parity-fixtures.py

   spikes/
     OverlayHarness/

   research/
     feature-parity.md
     architecture.md
     dependencies-permissions.md
     packaging-installation.md
     implementation-plan.md
```

Commit the NuGet `packages.lock.json` generated beside each project.

Link shared guide/media into the Windows project from the existing repository resources instead of duplicating them:

- `Resources/Data/guide-bundle.json`
- `Resources/CompanionPortraits`
- `Resources/ItemIcons`
- `Resources/BuildOptionIcons`
- `Resources/twilight-cleric.webp`

MSBuild `Content` items can assign package-relative `Link` paths, giving both builds one committed asset source. Generate/commit a JSON spell catalog for Windows from the existing canonical generator because Swift generated source cannot be consumed by C#. Do not require Python during player install or app runtime.

## Ordered milestones

### M0 — Windows platform proof harnesses

Estimate: 6–8 engineer-days

Goal: prove the hard OS/GPU/package assumptions before product UI is ported.

Tasks:

1. Create the x64 .NET 10 WPF skeleton, package identity, test project, and self-contained development MSIX.
2. Overlay harness: transparent/topmost/tool-window/no-activate behavior, explicit text activation, drag/resize, per-monitor-v2 DPI, and BG3-relative bounds.
3. Game harness: locate `bg3.exe` and `bg3_dx11.exe`, follow window/foreground changes, and launch the Steam URI without elevation.
4. Controlled x64 game-window hosts named `bg3.exe` and `bg3_dx11.exe`: movement, resizing, minimize/restore, close/relaunch, foreground changes, negative coordinates, and Windowed/Borderless-style geometry.
5. Package services: Credential Manager round trip/delete, startup-task states, and clean install/uninstall.

Required real-hardware matrix:

- Both controlled exact-name x64 hosts (`bg3.exe` and `bg3_dx11.exe`); no live BG3 installation is required.
- Windowed and Borderless-style controlled geometry; true exclusive full-screen remains unsupported.
- one and two monitors at 100%, 150%, and 200% DPI, including negative monitor coordinates and moves between monitors.
- Windows 11 24H2, 25H2, and 26H1 x64 clean VMs/devices where available.

Exit gate G0:

- All harness results and logs are recorded without claiming live BG3 renderer, gameplay, or input compatibility.
- No process injection, admin, service, local port, hidden capture, or graphics hook is needed.
- Product/package scans prove screenshot/capture/clipboard-image and microphone/speech code, UI, and capabilities are absent.
- If WPF cannot pass the overlay matrix, stop and evaluate WinUI 3 against the same harness before product work. Do not move to a web shell.

### M1 — Core model, resources, and persistence

Estimate: 2–3 engineer-weeks

Goal: make macOS domain behavior executable and testable on Windows before building screens.

Tasks:

1. Port the Swift data models and JSON fixtures with explicit `System.Text.Json` names/options.
2. Port deterministic current-goal, route/readiness, run creation/version migration, party, build, gear, and act-transition rules.
3. Implement guide/resource loader and committed Windows spell-catalog generation.
4. Implement SQLite schema, migrations, transactional snapshot/revision write, 20-revision pruning, settings, imported builds, and internal pre-migration recovery copies.
5. Port the 41 live macOS tests (47 total minus six unreachable backend endpoint tests) and add serialization/resource-count golden tests.

Exit gate G1:

- Shared fixture inputs produce equivalent semantic results on macOS and Windows for every ported test.
- Guide version, three payloads, route availability, 11 portraits, 51 item icons, and 697 build-option icons validate.
- Act 2 route absence is represented explicitly.
- Crash/restart tests never expose a partially committed run.
- No runtime dependency on Python, the legacy backend, or Ollama.

### M2 — Shell, onboarding, runs, Now, Route, and overlay

Estimate: 3–4 engineer-weeks

Goal: deliver the complete local assistant loop without AI.

Tasks:

1. Build single-instance app lifetime, tray menu, planner/settings windows, Steam launch, and game-detection coordinator.
2. Build onboarding fresh/mid-run flows, difficulty/spoiler choices, party/level catch-up, guide-only/OpenRouter choice, startup toggle, and replay tour.
3. Build run creation/switch/rename/settings and guide-version migration UI.
4. Build collapsed pet/focus/reference overlays and expanded Now/Route views.
5. Implement geometry/persistence, step detail, completion/skip/revisit/caught-up, warnings/confirmations, fight pin/mute/snooze, gear target, archived sections, and external map actions.

Exit gate G2:

- Parity rows O-01–O-18, R-01–R-15, S-01–S-05, S-07, S-09, and persistence rows I-01/I-03/I-09 pass.
- A fresh player can complete onboarding, generate the Steam launch URI, detect either controlled host, follow and update a route, quit, restart, and recover exact state with the network disconnected.
- Every overlay mode passes the G0 controlled-host/DPI matrix.
- Act 2 visibly says route content is unavailable; no empty or invented guidance appears.

### M3 — Party, builds, loadout, and act ledger

Estimate: 3.5–4.5 engineer-weeks

Goal: complete all non-AI planning surfaces.

Tasks:

1. Party roster/status/swap/hireling/member detail, respec/reset, and undo.
2. Reviewed build display/comparison/assignment.
3. Manual build planner, levels/classes/multiclass/subclasses/feats/spells/options/icons, point-buy validation, and ability recipes.
4. Gear paper doll, targets, ownership/conflicts, alternative overrides, route pickups, and detail/map/wiki actions.
5. Act browse/preview/history, gear review, route consequence acceptance, immutable transition records, and final lock.

Exit gate G3:

- Parity rows P-01–P-18 pass.
- Current Swift gear/build/act/run-safety fixtures pass as Windows tests.
- Keyboard-only navigation, high contrast, screen-reader labels, focus order, and 200% scaling are usable.
- No missing icon or unknown catalog entry silently removes a choice/item.

### M4 — Typed OpenRouter and secure build import

Estimate: 2.5–3.5 engineer-weeks

Goal: add optional typed network features without changing the local-guide trust boundary.

Tasks:

1. Credential Manager Save/Replace/Test/Remove and redaction tests.
2. Direct `HttpClient` OpenRouter client, grounded prompt builder, scopes/history/quick prompts, structured-output validation, Markdown/source display, cancellation/timeouts, and explicit errors.
3. Pin `google/gemini-3.6-flash` in one release setting; CI verifies model existence plus text/structured-output capabilities before release.
4. Secure HTTPS build importer with per-hop DNS/redirect validation, caps, AngleSharp/PdfPig parsing, structured build validation, verify label, persistence, and assignment.
5. Enforce the approved screenshot/capture/clipboard-image and microphone/speech exclusions with source, manifest, dependency, and unpacked-package tests.

Exit gate G4:

- Parity rows A-01–A-10, P-06/P-07, S-06/S-08/S-10/S-11, and I-04 pass.
- A live smoke test returns a real typed OpenRouter response using scoped text context.
- Invalid key, insufficient credits/rate limit, timeout, offline, provider error, malformed response, and removed model each produce an explicit error; none fabricates a fallback answer.
- Test transport proves no `Authorization` header/key, prompt, or chat content enters logs or persistent storage.
- Build-import SSRF suite blocks private/reserved DNS, IPv4/IPv6, rebinding/redirect cases, oversized content, and unsupported content.
- Package inspection proves no capture, clipboard-image, microphone, speech, or dictation feature is shipped.

### M5 — Packaging, hardening, release candidate

Estimate: 2–3 engineer-weeks plus Store/signing lead time

Goal: produce a player-installable, signed, updateable x64 release candidate.

Tasks:

1. Finalize package identity, manifest, icons, startup extension, LocalState paths, notices, privacy text, SBOM, and App Installer feed; declare no microphone or capture capability.
2. Add Windows CI, clean-VM install/update/uninstall tests, package inventory/security assertions, signature/hash verification, and Defender scan.
3. Exercise schema and guide-version upgrades from every internal prerelease fixture; test internal recovery-copy and failed-migration behavior.
4. Run the full controlled-host display matrix plus startup/credential denial and failure checks. Live BG3 is outside this MVP release gate.
5. Update player README from “Planned” to exact verified links/screens only after the signed artifact exists; submit stable candidate to Store and signed beta to canonical HTTPS feed.

Exit gate G5:

- Parity rows I-02/I-05–I-14 and every prior gate pass.
- Clean Windows 11 x64 install needs no admin, developer tools, runtime, model, or server.
- Signature/publisher/timestamp/hash/SBOM/Defender records match the uploaded bytes.
- Update preserves runs/settings/key; uninstall removes package/app data; external credential cleanup is documented and verified.
- There are no forbidden files, processes, ports, firewall rules, services, drivers, mods, or BG3 writes.

## Test strategy

### Automated on every Windows change

- xUnit tests for Core decisions and all ported Swift fixtures.
- Golden JSON round trips for guide/run/imported-build compatibility.
- SQLite transaction, revision, migration/recovery-copy, corruption, and failure tests.
- `HttpMessageHandler` contract tests for OpenRouter and import redirects/errors/redaction.
- Platform adapter tests behind fakes plus Windows integration tests for mutex, HWND selection fixture, Credential Manager, startup state, and LocalState.
- Package tests that unpack MSIX, validate manifest/architecture/resources/notices, and reject forbidden names/extensions/content.

### Automated on release candidates

- Clean-VM install, first launch, update from previous signed/internal package, repair, and uninstall.
- Windows UI Automation smoke for onboarding, tray-to-overlay, route completion, key management, and accessibility names/focus.
- Live OpenRouter canary using a restricted CI key and minimal spend; never run on forks and never persist output containing the key.
- Signature, publisher, timestamp, SHA-256, SBOM, dependency-vulnerability, and current Defender verification.

### Manual controlled-overlay hardware matrix

| Dimension | Required cases |
|---|---|
| Controlled process | exact-name x64 `bg3.exe`, `bg3_dx11.exe` |
| Display geometry | Windowed-style, Borderless-style |
| OS | supported Windows 11 x64 release floor, current mainstream release, new-device 26H1 where obtainable |
| Monitors | single, dual; game on primary and secondary; negative coordinate layout |
| DPI | 100%, 150%, 200%; move game between monitors |
| Window state | foreground/background, moved, minimized/restored, resized, closed, relaunched |
| Permissions | startup enabled/DisabledByUser; Credential Manager save/read/delete and access failure |
| Network | online, offline, proxy, DNS failure, TLS failure, timeout, OpenRouter auth/rate/provider errors |

Do not replace physical monitor/DPI, clean-machine package lifecycle, or live OpenRouter checks with source inspection alone. Do not claim live BG3 testing.

## Feature-parity gates

| Gate | Meaning | Blocking evidence |
|---|---|---|
| G0 Platform | OS/window/package assumptions proven | controlled-host harness log plus physical display results |
| G1 Domain | source behavior and data ported | 41 live test equivalents plus resource/golden tests |
| G2 Core UX | local route assistant complete | onboarding/run/overlay/Now/Route end-to-end |
| G3 Planning | party/build/gear/act complete | all P rows and accessibility pass |
| G4 Optional network | typed OpenRouter/import complete; capture/speech exclusions enforced | live provider response, HTTP-security suite, and unpacked-package exclusion scan |
| G5 Distribution | install/update/uninstall/signing complete | clean signed artifact evidence |

Release requires G0–G5. An optional-feature defect may ship only if the feature is removed from the package/UI and its parity row is changed to an explicitly approved exclusion; it may not be silently hidden.

## Risks and exit criteria

| Risk | Trigger | Control | Exit criterion |
|---|---|---|---|
| Overlay disappears/steals focus | controlled host or DPI harness fails | correct HWND styles/events; require borderless/windowed; keep overlay bounds small | both exact-name x64 hosts pass without foreground theft |
| WPF transparent rendering defect | high GPU/blur/text issue | simplify visual effects first; only then compare WinUI 3 harness | stable frame/input behavior at all DPIs |
| macOS state semantics drift | fixture mismatch | port pure rules first; cross-platform golden fixtures | zero unexplained semantic differences |
| Current source fallback conflicts with provider policy | provider failure returns bundled prose | Windows explicit errors; contract test forbids fallback | real response or explicit failure only |
| Act 2 route is absent | empty payload | visible data-gap state; no fabricated content | parity and transition behavior match source |
| SmartScreen/Defender friction | signed beta warns/flags | Store stable, consistent signature, conventional package, Defender submission process | verified publisher; no unsafe bypass docs |
| MSIX credential residue | uninstall leaves key | in-app Remove key plus manual Credential Manager instructions | tested/documented cleanup |
| Dependency supply-chain issue | vulnerability/advisory | lock, SBOM, audit, minimal packages | zero unreviewed critical/high findings |
| Model churn | pinned slug removed/capability changes | release-time models check; explicit unavailable error; deliberate version update | live text/structured canary passes |
| 32-bit/ARM scope pressure | request appears | separate architecture proposal/estimate | x64 artifact remains accurately labeled |

## Effort estimate

Expected engineering effort: **15–20 engineer-weeks** for one experienced Windows/.NET engineer, plus external calendar time for signing identity validation and Store review.

| Work | Estimate |
|---|---:|
| M0 platform harnesses | 1.2–1.6 weeks |
| M1 core/data/persistence | 2–3 weeks |
| M2 shell/onboarding/runs/route/overlay | 3–4 weeks |
| M3 party/builds/gear/acts | 3.5–4.5 weeks |
| M4 typed OpenRouter/import | 2–3 weeks |
| M5 packaging/hardening/release | 2–3 weeks |

Two engineers can overlap M2 and M3 after G1, but M0/G1 and final packaging gates remain serial. A realistic two-engineer calendar is roughly 9–12 weeks, not half the one-engineer estimate.

Estimate exclusions:

- creating missing Act 2 route content;
- 32-bit x86 or ARM64;
- localization;
- cloud sync/account system;
- a new map platform;
- BG3 mod/injection integration;
- redesigning the shared macOS product.

## Definition of implementation acceptance

The follow-up build goal is complete only when:

1. Every row in `feature-parity.md` has linked test/manual evidence or a still-approved explicit exclusion/data gap.
2. A clean supported Windows 11 x64 machine installs one signed package without admin, developer tools, or a separate runtime.
3. The overlay follows both controlled exact-name x64 hosts in Windowed/Borderless-style geometry without stealing foreground input; no live BG3 claim is required or permitted.
4. Runs, routes, party, builds, gear, acts, onboarding, settings, startup, persistence, and bundled assets match the source behavior.
5. OpenRouter is the only AI path; a live typed-text request succeeds directly, and all provider failures are explicit.
6. Screenshot/capture/clipboard-image and microphone/speech features are absent from product UI, services, package capabilities, dependencies, and delivered bytes.
7. Key, prompts, and chat content are absent from package files, SQLite, logs, diagnostics, and crash artifacts.
8. Install, upgrade/migration recovery, repair, uninstall, signing, Defender, and SmartScreen documentation are verified against the exact release artifact.
9. No Python, Node, Ollama, local model, server, service, port listener, driver, mod, injection, BG3 file/save write, or elevation is present.
10. `/mac` continues to build/test unchanged apart from explicitly reviewed shared-resource pipeline work.

## Official implementation references

- [WPF windows and transparency/topmost behavior](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/)
- [Win32 extended window styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)
- [Credential Manager `CredWriteW`](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew)
- [Packaged startup tasks](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask?view=winrt-26100)
- [MSIX packaging](https://learn.microsoft.com/en-us/windows/msix/overview)
- [App Installer automatic updates](https://learn.microsoft.com/en-us/windows/msix/app-installer/auto-update-and-repair--overview)
- [MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [OpenRouter direct API quickstart](https://openrouter.ai/docs/quickstart)
- [Current planned OpenRouter model](https://openrouter.ai/google/gemini-3.6-flash)
