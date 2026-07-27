# Windows parity evidence ledger

> Generated from `research/feature-parity.md`. Update Status and Evidence as tests are completed;
> rerunning this generator intentionally resets rows to Pending.

## 2026-07-27 ARM64 completion checkpoint

This checkpoint supersedes stale `Pending` notes below where the newer evidence
directly covers the row. It applies only to `arm64`/`win-arm64`; no x64/AMD64
build, review, package, or test was performed in this milestone.

| Area | Status | Current evidence |
|---|---|---|
| Fresh onboarding, shell, overlay, tray, Now, Route, Party, Loadout, Act, Settings | Manual pass plus automated pass | Signed MSIX iterations through 0.2.0.11 were exercised at 200% DPI. The 57-capture packaged matrix, clean first launch, and action index are in `evidence/arm64-completion/`. Controller/UI tests cover routing, roster/build/gear/act actions and transient undo. |
| Mid-run catch-up, multiple runs, revisions, persistence | Manual pass plus automated pass | Fresh/Act 1/2/3 onboarding, landmark catch-up, two runs, switching, rename, and upgrade persistence were exercised. App/infrastructure tests cover serialized transitions, revisions, recovery, and SQLite durability. Final uninstall removed LocalState; reinstall reproduced clean onboarding. |
| Credential Manager and direct OpenRouter | Automated pass plus packaged UI observation | Settings exposed only configured/not-configured state, replace/test/remove, and the pinned model. The key value was never read or printed. HTTP stubs cover success, cancellation, authentication, rate limit, timeout, provider, malformed response, offline, and response limits. Live canary remains opt-in and disabled by default. |
| ARM64 package/product boundary | Automated pass plus manual package pass | Exact signed 0.2.0.11 passed signature verification, native ARM64 MakeAppx unpack, recursive pre/post validation, install, native-process probe, upgrades, uninstall, and reinstall. Architecture evidence reports 487 publish PEs and 486 packaged PEs with no foreign native payload; the package contains 695 build PNGs, 51 item PNGs, and zero WebPs. |
| Full final-state visual matrix | Manual pass with recorded limitation | All 57 non-provider oracle rows have real packaged captures and an action index. Row 15 is absent from the oracle. Rows 49/50 require an unapproved live request; they have deterministic client/decode coverage and source/action review, not runtime screenshots. See `evidence/arm64-completion/defects.md` (`WIN-QA-001`). |

| Row | Gate | Status | Evidence |
|---|---|---|---|
| O-01 | G2 | Pending | Partial automated pass: the production `NotifyIcon` command model now contains Show Overlay, Planner, Map, dynamic run switcher, Steam launch, Hide/Show Pet, Settings, and Quit; action invocation and state refresh tests pass. Visible clean-VM tray interaction remains outstanding. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| O-02 | G2 | Pending | Partial: `Windows/SingleInstance/SingleInstanceService.cs`; multi-launch UI activation remains outstanding. |
| O-03 | G2 | Automated pass | `GameLauncher` owns the exact `steam://run/1086940` URI and shell execution; unit/package contracts verify no live Steam or BG3 launch is required. Planner and tray route to the same error-reporting action. |
| O-04 | G2 | Pending | Partial automated pass: exact-name x64 `bg3.exe`/`bg3_dx11.exe` controlled hosts cover detection, movement, resize, minimize/restore, and close on one display. See `evidence/G0/controlled-window-matrix-2026-07-25.md`; remaining physical matrix and G2 visibility rule are outstanding. |
| O-05 | G2 | Pending | - |
| O-06 | G2 | Pending | Partial automated pass: passive topmost/no-activate placement preserves foreground and deliberate activation removes `WS_EX_NOACTIVATE` against both controlled hosts. See `evidence/G0/controlled-window-matrix-2026-07-25.md`; product text-entry UX and physical matrix remain outstanding. |
| O-07 | G2 | Pending | - |
| O-08 | G2 | Pending | Partial automated pass: controlled hosts cover move/resize/negative-coordinate/minimize/restore/close at live 200% DPI; 100/150/200% conversion tests pass. Physical two-monitor and 100/150% runs remain outstanding. See `evidence/G0/controlled-window-matrix-2026-07-25.md`. |
| O-09 | G2 | Pending | Partial controlled/product pass: real pointer drag preserved controlled-host foreground, normalized/clamped anchor math passes negative-coordinate cases, SQLite preferences survive restart, and the exact product rectangle was restored. Physical two-monitor/100%/150% interaction remains outstanding. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| O-10 | G2 | Pending | - |
| O-11 | G2 | Automated pass | Minimal, Focus, and Reference density surfaces are wired to the persisted enum, Settings, focus context menu, and collapse action; size and 100/150/200% physical conversion tests pass. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| O-12 | G2 | Automated pass | The exact Mac jump/idle/look/reduced-motion state machine is ported and tested; Windows native decode/crop tests prove the committed WebP atlas, and product UI Automation found the accessible resting pet. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| O-13 | G2 | Pending | Partial controlled/product pass: UI Automation found current action, level, danger/avoid, Route/Ask/Task done/Collapse shortcuts and the context-owned snooze/mute/pin/density actions; real Collapse preserved controlled-host foreground. Remaining action-by-action UI and confirmation evidence is outstanding. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| O-14 | G2 | Automated pass | The native WPF planner exposes Now, Route, Party, Loadout, Act, Chat, Settings, and Diagnostics tabs; overlay/tray actions route to owned tabs and no web shell is present. |
| O-15 | G2 | Pending | - |
| O-16 | G2 | Pending | - |
| O-17 | G2 | Pending | - |
| O-18 | G2 | Pending | - |
| R-01 | G2 | Pending | - |
| R-02 | G2 | Pending | Partial automated pass: fresh-run domain test preserves reusable character/build presets while resetting progress, story, gear, act, level, and modifiers. UI workflow remains outstanding. See `evidence/G1/mac-oracle-test-port-2026-07-25.md`. |
| R-03 | G2 | Automated pass | SQLite tests prove atomic snapshots/revisions, per-run 20-revision pruning, and newest-valid-revision fallback. See `Infrastructure.Tests/Persistence/RunRepositoryTests.cs` and `evidence/G1/mac-oracle-test-port-2026-07-25.md`. |
| R-04 | G2 | Pending | - |
| R-05 | G2 | Pending | Partial automated pass: `Core/Route/CurrentGoal.cs` and `Core.Tests/Route/CurrentGoalTests.cs` prove gear-target → unavailable-act → walkthrough → checkpoint → complete priority, presentations, and the exact Act 2 data-gap message. WPF Now/Route integration remains outstanding. |
| R-06 | G2 | Pending | Partial: readiness/blocker behavior in `Core.Tests/Route/RunSafetyTests.cs`. |
| R-07 | G2 | Pending | - |
| R-08 | G2 | Pending | - |
| R-09 | G2 | Pending | Partial: caught-up/dependency/consequence cases in `Core.Tests/Route/RunSafetyTests.cs`. |
| R-10 | G2 | Pending | - |
| R-11 | G2 | Pending | - |
| R-12 | G2 | Pending | - |
| R-13 | G2 | Pending | - |
| R-14 | G2 | Pending | - |
| R-15 | G2 | Data gap | The shared guide loader and tests enforce an empty Act 2 route payload; UI must display the mandated data-gap message and never invent content. See `Infrastructure.Tests/Resources/GuideRepositoryTests.cs`. |
| P-01 | G3 | Pending | Partial automated pass: `Core.Tests/Models/HonorRunBehaviorTests.cs` proves all 12 oracle roster entries, default statuses, four-active cap, status eligibility, active-party projection, and complete party-plan snapshot/restore. Party UI, hirelings, swaps, respec, and undo remain outstanding. |
| P-02 | G3 | Pending | - |
| P-03 | G3 | Pending | - |
| P-04 | G3 | Pending | - |
| P-05 | G3 | Pending | - |
| P-06 | G3 | Automated pass | Public HTTPS:443-only HTML/text/PDF loading is bounded to 5 MB/60,000 characters, manually validates every redirect and DNS result, revalidates at socket connect, rejects private/reserved/rebinding targets, and uses strict structured output. Product URL import UI is present. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| P-07 | G3 | Pending | Partial automated pass: legal 27-point buy, distinct bonuses, level bounds/duplicates, level-12 split validation/repair, imported/verify marker, global SQLite save/reload/delete, assigned-delete protection, and controller assignment are tested. Final replace-confirmation UX remains outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| P-08 | G3 | Pending | Partial automated pass: 12 classes through level 12, multiclass propagation, critical conditional choices, embedded generated spell facts, >1,000 option entries, and referenced artwork presence are tested. Remaining catalog/UI comparison evidence is outstanding. |
| P-09 | G3 | Pending | - |
| P-10 | G3 | Pending | Partial automated pass: `AbilityProgressionTests.cs` and `AbilitySourceRulesTests.cs` cover point buy, reset/ASI parsing, setup selection, complete source breakdown, equipment minimums, consumable replacement, source order, act/level gates, ownership, and unique-across-party rules. Recipe UI remains outstanding. |
| P-11 | G3 | Pending | Partial automated pass: canonical slot classification covers cape, instrument, torch/extras, and the full slot enum; paper-doll UI remains outstanding. |
| P-12 | G3 | Pending | Partial automated pass: typed guide golden round trip preserves complete gear metadata (effect, acquisition, wiki, icon, coordinates, availability, alternatives, and map-objective flag). Detail UI and outbound map/wiki actions remain outstanding. |
| P-13 | G3 | Pending | - |
| P-14 | G3 | Pending | Partial automated pass: deterministic override, earliest assignment, and stable name tie-break logic are implemented and tested; UI conflict resolution remains outstanding. |
| P-15 | G3 | Pending | - |
| P-16 | G3 | Pending | Partial automated pass: past/current/future act-lock model tests pass; ledger UI remains outstanding. |
| P-17 | G3 | Pending | - |
| P-18 | G3 | Pending | Partial automated pass: final Act 3 record locks its ledger and preserves immutable gear-review status; finalization UI/gates remain outstanding. |
| A-01 | G4 | Approved exclusion | Windows exposes no local/Ollama model capability. Negative capability tests and product/package scans enforce OpenRouter-only scope. See `evidence/G1/mac-oracle-test-port-2026-07-25.md`. |
| A-02 | G4 | Automated pass | One lazy production `HttpClient` posts directly to OpenRouter with Bearer auth; contract/package tests forbid SDK/proxy/local-server alternatives. A real opt-in canary passed. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| A-03 | G4 | Automated pass | The single pinned model constant is `google/gemini-3.6-flash`; its text, structured-output, and mandatory-reasoning metadata were verified against OpenRouter's public catalog, then the exact client passed a live strict-schema canary. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| A-04 | G4 | Automated pass | Core tests prove current/route/party scoping, current-step priority, bounded route context, recent eight turns, sources, quick-prompt inputs, strict answer JSON, Markdown-safe HTTPS links, and Act 2 gating. A product UI Automation smoke returned a real provider answer. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| A-05 | G4 | Automated pass | Chat history exists only in the WPF window process and clears explicitly/on run or act change/on exit. A product smoke cleared chat and found the exact prompt absent from SQLite; package tests reject chat/prompt persistence paths. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| A-06 | G4 | Automated pass | Provider/authentication/credit/rate/model/timeout/network/malformed errors are explicit and redacted; tests prove no fallback answer or response-body leak. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| A-07 | G4 | Approved exclusion | Windows MVP has no screenshot/image attachment feature; product code, UI, and capabilities removed. See `evidence/mvp-scope-2026-07-25.md`. |
| A-08 | G4 | Approved exclusion | Windows MVP performs no frame capture, HDR conversion, image persistence, or image upload. See `evidence/mvp-scope-2026-07-25.md`. |
| A-09 | G4 | Approved exclusion | Windows MVP requests no microphone access and has no speech/dictation feature or capability. See `evidence/mvp-scope-2026-07-25.md`. |
| A-10 | G4 | Automated pass | Prompt/UI integration enforces the exact `Act 2 route is not available in this guide version` route-availability gate and does not send invented route context. See `Core.Tests/Chat/ChatPromptBuilderTests.cs` and `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| S-01 | G2/G4 | Pending | Partial automated pass: fresh/mid-run versioned step sequences are ported; WPF wizard/replay/resume remain outstanding. |
| S-02 | G2/G4 | Pending | Partial automated pass: offered difficulty list and Explorer/Custom overlay model behavior match the oracle; UI remains outstanding. |
| S-03 | G2/G4 | Pending | - |
| S-04 | G2/G4 | Pending | Partial automated pass: catch-up marks through the chosen landmark inclusively and preserves explicit history; WPF flow remains outstanding. |
| S-05 | G2/G4 | Pending | - |
| S-06 | G2/G4 | Pending | Partial automated pass: product/package tests and UI inspection prove OpenRouter is the only provider surface, the guide remains usable without a key, and no local-model controls exist. Final onboarding copy/workflow evidence remains outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| S-07 | G2/G4 | Pending | - |
| S-08 | G2/G4 | Pending | Partial product pass: Settings exposes key configured state, save/replace, connection test, remove, and the pinned model without revealing the key. Remaining applicable overlay/run/legal controls and full UI automation remain outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| S-09 | G2/G4 | Pending | Partial: disabled-by-default startup manifest, explicit enable/disable UI, and a signed-development MSIX run that observed off -> on -> off; clean-VM and production-package evidence remain outstanding. |
| S-10 | G2/G4 | Pending | Partial automated/product pass: diagnostics report provider configured/not configured and pinned model only; package tests reject key/prompt/chat persistence. Remaining package version, signing channel, and full process/window diagnostics evidence is outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| S-11 | G2/G4 | Pending | - |
| I-01 | G1/G5 | Pending | Partial automated pass: WAL/foreign keys/busy timeout, schema v1-to-v2 migration, pre-migration backup, failed-migration rollback, corruption preservation, active-run transaction, 20 revisions, fallback recovery, settings, and patched SQLite are tested. MSIX LocalState integration remains outstanding. |
| I-02 | G1/G5 | Pending | Partial automated pass: imported builds persist/update/delete in the same SQLite database and remain globally reusable across controller restart; assignment and assigned-delete protection are tested. Final replace-confirmation UX and packaged servicing evidence remain outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| I-03 | G1/G5 | Pending | Partial automated/product pass: overlay density/visibility/reduced-motion/normalized anchor persist in SQLite; snooze, pin, active dialogs, undo, and chat remain transient. A controlled-host drag restored the exact rectangle after restart. Remaining packaged update-boundary evidence is outstanding. See `evidence/G2/overlay-shell-anchor-pet-2026-07-25.md`. |
| I-04 | G1/G5 | Automated pass | Win32 Credential Manager generic credentials support trimmed save/replace/read/delete under `BG3HonorAssistant/OpenRouter`; a live provider canary used the production target, Settings exposes only safe controls/status, and package scans reject SQLite/package/log key paths. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| I-05 | G1/G5 | Approved exclusion | The unreachable local-backend lifecycle and its six endpoint tests are not ported. No local/inbound server is permitted. See `evidence/G1/mac-oracle-test-port-2026-07-25.md`. |
| I-06 | G1/G5 | Approved exclusion | Ollama, local models, runtime discovery/downloads, daemons, and model UI are forbidden and absent; negative capability/package tests enforce this. |
| I-07 | G1/G5 | Pending | - |
| I-08 | G1/G5 | Pending | Partial automated pass: shared guide validation plus typed decode/re-encode/decode preserves route decisions, incidents, risk/reward, acts, items, complete gear/ability metadata; generated spell catalog, artwork presence, source inventory, and Act 2 gap checks pass. Exact rebuilt MSIX inventory remains outstanding. |
| I-09 | G1/G5 | Pending | - |
| I-10 | G1/G5 | Automated pass | All 41 live Mac behavior tests are represented in xUnit; the six unreachable backend endpoint tests are the documented exclusion. With additional oracle/compatibility, persistence, HTTP-security, Windows platform, app-controller, and package coverage, 267 automated tests pass with zero failures/skips. See `evidence/G1/mac-oracle-test-port-2026-07-25.md`, `evidence/G4/typed-openrouter-import-2026-07-25.md`, and `evidence/automated-baseline.md`. |
| I-11 | G1/G5 | Pending | - |
| I-12 | G1/G5 | Pending | Partial: `package/Package.appxmanifest`, self-contained pack scripts, and `evidence/G0/development-package-2026-07-25.md`; production signing, install, update, uninstall, and clean-VM evidence remain outstanding. |
| I-13 | G1/G5 | Pending | Capture and microphone portions are approved exclusions in `evidence/mvp-scope-2026-07-25.md`. Partial remaining evidence: package/product scans find no related UI or capabilities; disabled-by-default packaged startup observed off -> on -> off; production Credential Manager and direct outbound HTTPS passed. Clean-VM and exact delivered-byte boundaries remain outstanding. See `evidence/G4/typed-openrouter-import-2026-07-25.md`. |
| I-14 | G1/G5 | Pending | Partial: temporary self-signed SignTool experiment and exact user/machine certificate cleanup are recorded in `evidence/G0/packaged-permissions-2026-07-25.md`; trusted production signature/timestamp/SmartScreen evidence remains outstanding. |

Allowed statuses: `Pending`, `Automated pass`, `Manual pass`, `Approved exclusion`, `Data gap`, `Blocked`.
