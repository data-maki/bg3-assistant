# Product-flow independent review

## Q/A before experiments

**Hypothesis.** The worker fixes may pass their focused tests while still diverging from the live mac behavior at boundary conditions: conditional prerequisite choices may trust caller-supplied metadata, inactive companions may be mutated during batch leveling, route focus may leak unrelated encounters, decision outcomes may be ignored, or contested loadout ownership may remain ambiguous.

**Evidence available.** Worker commit `52fc561436cc1848b9a1e36fe34994b867631ab2`; Windows Core/App sources and tests in this worktree; live `/mac` source as a read-only behavioral oracle; deterministic test execution through `C:\Users\jcarbs\AppData\Local\Microsoft\dotnet-arm64\dotnet.exe` with explicit `RuntimeIdentifier=win-arm64` and `PlatformTarget=arm64`.

**Unknowns.**

- Whether every one of the 12 supported classes has complete and semantically correct prerequisite metadata.
- Whether conditional choices are validated from canonical catalog metadata rather than a caller-provided copy.
- Whether inactive-roster state is stable across batch leveling.
- Whether focused routes preserve checkpoint ordering, earliest-active fallback, and decision outcomes.
- Whether loadout swaps preserve unique ownership and contested-owner selection remains reachable.
- Whether resource lookup fixes for BG3-WIN-006/007 work outside a repository-shaped directory tree.
- Whether the changed code introduces prohibited local servers/models, mods/injection, elevation, or player-runtime dependencies.

**Acceptance tests.**

1. Inspect the worker diff and compare product semantics with live `mac/BG3Assistant/ManualBuild.swift`, `ManualBuildPlannerView.swift`, and `AppState+Party.swift` without modifying macOS sources.
2. Challenge prerequisites, all 12 class definitions, inactive roster leveling, route focus/fallback/decision outcomes, loadout swaps, contested ownership, and controller/UI reachability.
3. Build/test with explicit `RuntimeIdentifier=win-arm64` and `PlatformTarget=arm64` through the ARM64 .NET host; label this native-ISA ARM64 inside a Parallels VM, never physical-device proof.
4. Confirm the owned product source contains no local server/model, mod/injection, elevation, or player-runtime behavior.
5. Accept only if deterministic ARM64 suites pass and no counterexample remains; otherwise make the minimum owned-file fix and regression test.

## Independent invalidation result

### RPR-001: caller-provided choice metadata bypassed manual-build prerequisites

- Architecture: both (managed product logic); fixed and regression-tested under `win-arm64`.
- Severity: high, because a non-UI caller could persist a conditional choice that the catalog marks unavailable.
- Reproduction: establish Wizard through character level 4, take the canonical `ability-improvement-4` group, clone it with `RequiredSelection = null`, and call `ToggleManualChoiceAsync` before selecting the feat. Worker code evaluated the supplied clone and returned `true`.
- Root cause: `ToggleManualChoiceAsync` treated its `BuildChoiceGroup` parameter as authoritative for prerequisite, option, maximum-selection, and persistence-key validation. The WPF UI passes catalog objects, but the claimed controller boundary remained forgeable.
- Fix: resolve the member's actual class level, find the canonical group by ID in that class-level definition, and use only canonical prerequisite/options/maximum/key data. Reject missing class levels and unknown groups.
- Regression test: `ManualBuildFlowRecordsClassFeatAndConditionalChoice` now first establishes Wizard at character level 1 so character level 4 is genuinely Wizard class level 4; it rejects both the canonical unavailable group and a forged prerequisite-free copy, then accepts the canonical choice after the prerequisite feat is selected.
- Reviewer result: the pre-fix source admits the constructed bypass because it evaluates only the supplied clone. After the fix, the adversarial regression and focused native-ISA ARM64 suite passed 4/4.
- Residual risk: serialized legacy plans are not proactively scrubbed of impossible old selections; the normal UI never created this forged state. A future normalization/migration audit may choose to clean such state, but that is outside this minimal boundary fix.

## Worker-finding challenge results

- **All 12 manual-build classes and prerequisites:** accepted after comparing the Windows catalog and prerequisite rule with live mac source. The Core suite's catalog tests cover all 12 classes through level 12, every class with representative live-mac features/special choices, feat conditional groups, same-level scope, subclass conditions, and artwork inventory. The reviewer found the controller forgery above and closed it.
- **Inactive roster leveling:** accepted. `SetAllPartyLevelsAsync` mutates only `RosterStatus.Active`; the isolated controller regression snapshots every camp/unrecruited level and verifies all inactive values remain unchanged.
- **Route focus and decisions:** accepted. A focused non-checkpoint step owns the current state and yields null checkpoint/readiness; direct decision completion is rejected; `ResolveOutcomeAsync` records the selected valid outcome and completes through the reviewed rules.
- **Loadout swaps and ownership:** accepted. Controller validation constrains swaps to a known item, current act, active member, and matching classified slot. The focused regression persists a same-slot override and contested owner. Read-only XAML/code-behind inspection confirms Change Pick, Revert, Party Conflict, and Give To controls are bound to reachable handlers.
- **UI reachability/build:** accepted at compile/test scope. The ARM64 App test build compiled the WPF views and event handlers. Packaged keyboard/mouse/DPI usability remains a higher-level QA gate.
- **Prohibited runtime boundary:** accepted. A scoped search of the changed Core/controller/loadout/party sources found no `HttpListener`, Kestrel, localhost endpoint, P/Invoke, elevation verb, process launch, or injection primitive. No mod, local model/server, admin, or BG3 player runtime was added.
- **macOS preservation:** accepted for this lane. macOS files were read only and remain unmodified.

## ARM64 experiments and results

Environment captured 2026-07-27:

- Windows 11 Pro `10.0.26200`, OS architecture `ARM 64-bit Processor`.
- Computer model `Parallels ARM Virtual Machine`, `HypervisorPresent=true`.
- PowerShell process architecture `Arm64`.
- .NET SDK/host `10.0.302` / `10.0.10`, host architecture `arm64`, RID `win-arm64`.
- Classification: **native-ISA ARM64 in a Parallels VM**. This is not physical Windows ARM64 device evidence.

Final commands used explicit `-r win-arm64 -p:RuntimeIdentifier=win-arm64 -p:PlatformTarget=arm64 -p:IsTestProject=true` through the ARM64 SDK. This worker branch predates the integrated dual-RID lockfile/build-target commit, so the reviewer temporarily force-evaluated ARM64 restore assets, restored every tracked lockfile, then ran final tests with `--no-restore`:

- `BG3HonorAssistant.Core.Tests`: **164 passed, 0 failed, 0 skipped**. Output/test assembly path included `win-arm64`.
- `ProductFlowControllerTests`: **4 passed, 0 failed, 0 skipped**. App and test outputs included `win-arm64`.
- Final tracked lockfile diff: none.

TRX files remain in ignored per-project `TestResults` directories and are not presented as integration evidence; the authoritative integration branch must rerun and retain its own matrix evidence after cherry-picking this review.

## Reflection and residual gates

The worker's product-flow fixes are accepted only with RPR-001's canonical-boundary correction. No further counterexample remained in the reviewed product scope. The code is managed and architecture-neutral; this ARM64 run demonstrates native-ISA execution in the VM, not physical hardware.

Still required outside this lane: integrate onto the dual-RID build base; locked arm64/x64 matrix restore/build/test/package inspection; x64 Windows CI; packaged ARM64 install/restart/upgrade/uninstall and end-to-end visual flows on physical Windows ARM64; multi-monitor/DPI coverage; and native-x64 physical validation as an explicit release gate.
