# Product flows lane

## Q/A before changes

### Hypotheses

1. The Windows domain models and controller partials preserve the live mac behavior
   for run creation, route progression, party/build planning, loadout/gear, and act
   transitions without depending on the forbidden local model/backend surface.
2. `BG3-WIN-006` is reproducible as analyzer warning xUnit2031 because at least one
   theory supplies data that cannot bind to its test method parameters.
3. The Core portion of `BG3-WIN-007` is reproducible because artwork/resource tests
   locate the repository through a fixed number of parent directories. That lookup
   is sensitive to configuration, architecture-first output layouts, and alternate
   test hosts.
4. Core flow behavior is architecture-neutral managed code. Any architecture-specific
   assumption in these models, rules, serializers, or tests is a defect.
5. The current tests port the known mac XCTest oracle, but deterministic controller
   flow tests may expose integration gaps between individually tested rules.

### Evidence

- The live mac behavior oracle is in `mac/BG3Assistant` and
  `mac/Tests/BG3AssistantTests`; the Windows equivalents are in the owned Core model,
  route, serialization, controller, and product-screen files.
- Existing evidence says 41 live non-backend mac XCTest behaviors were ported and
  deliberately excludes the six legacy local-backend endpoint tests.
- The Windows Core test project enables xUnit analyzers and treats warnings as errors.
  The baseline focused build failed at two `Assert.Single(sequence.Where(...))`
  calls with xUnit2031.
- `ManualBuildTests` searched upward for the Windows solution, then assumed the
  repository was exactly one parent above it and resources lived below
  `mac/BG3Assistant/Resources`. The live shared tree stores the canonical assets in
  top-level `Resources`.
- The live mac manual-build catalog exposes class features, class-specific choices,
  and conditional feat details. Windows exposed only subclasses, general feat names,
  spell lists, and three special class cases.
- The live mac batch-level action mutates only active party members. The Windows
  controller iterated the entire normalized roster.
- The live mac current-checkpoint selection returns no fight gate when the focused
  walkthrough step owns no checkpoint, and falls back to the earliest active step if
  every recommendation is dependency-blocked. Windows instead selected an unrelated
  checkpoint and omitted the active-step fallback.
- The mac completion action requires an explicit outcome for decision steps. The
  Windows UI guarded this, but the reusable controller method could still complete the
  step without an outcome.
- The live mac loadout lets the player substitute a reviewed item for a slot and
  resolve contested ownership. Equivalent Windows Core rules existed but no controller
  command or Loadout-screen control made either flow reachable.

### Unknowns

- Whether the new Loadout controls remain usable at every packaged DPI/window size;
  deterministic build/controller verification cannot replace physical UI exercise.
- Whether the coordinator's integrated build lane changes architecture-first output
  depth again; the new asset lookup searches ancestors for the canonical resource
  directory and is insensitive to that depth.
- Native ARM64 product-process behavior and x64 Windows CI execution are outside this
  managed product-flow lane.

### Acceptance tests

1. Reproduce xUnit2031, correct the theory contract, and run the affected test.
2. Demonstrate resource/artwork lookup succeeds without a fixed parent count from an
   architecture-first or otherwise deep test-host base directory.
3. Compare all owned product-flow logic with the live mac source/tests and disposition
   every material mismatch; preserve the Windows prohibition on local servers/models.
4. Add deterministic tests for uncovered run/route/party/build/loadout/act composition
   using isolated temporary state where persistence is needed and no server.
5. Run the focused Core/product App tests and record OS, process architecture, command,
   pass/fail counts, findings, and residual risk without claiming native-x64 hardware.

## Findings

### BG3-WIN-006: xUnit2031 stopped the Core build

- Architecture: both managed targets; reproduced under x64-on-ARM64 emulation.
- Severity: medium (matrix build blocker).
- Reproduction: locked restore, then build
  `BG3HonorAssistant.Core.Tests.csproj` with warnings as errors. The build failed at
  both filtered `Assert.Single` calls in `RoutePlannerRulesTests`.
- Root cause: the tests called `Where` before `Assert.Single`, which xUnit analyzer
  1.18 rejects in favor of the predicate overload.
- Fix: use `Assert.Single(collection, predicate)` at both sites.
- Regression test: the focused Core build succeeds with zero warnings/errors and the
  full Core suite passes.
- Reviewer result: independent invalidation review pending.
- Residual risk: none known.

### BG3-WIN-007 (Core): shared artwork lookup assumed repository shape

- Architecture: both.
- Severity: high (deterministic resource test failure / misleading artifact evidence).
- Reproduction: after clearing BG3-WIN-006, run
  `ManualBuildTests.EveryCatalogChoiceHasBundledArtwork`; it cannot find the old
  `mac/BG3Assistant/Resources/BuildOptionIcons` path in the current shared tree.
- Root cause: lookup first found the Windows solution, then depended on a fixed parent
  relationship and stale mac-local resource location.
- Fix: walk ancestors from the arbitrary test-host base and select the canonical
  `Resources/BuildOptionIcons` directory directly.
- Regression test: artwork inventory passes, plus a deep synthetic
  `architecture/configuration/framework/rid/publish` start path resolves without any
  fixed parent count.
- Reviewer result: independent invalidation review pending.
- Residual risk: App/Infrastructure resource-test paths are owned by other lanes and
  are not changed here.

### WIN-PROD-001: manual builds omitted live class and feat choices

- Architecture: both.
- Severity: high (core planning data unavailable).
- Reproduction: compare `ClassCatalog` with live
  `mac/BG3Assistant/ManualBuild.swift`; for example, Windows had no Bard Expertise,
  Fighter Eldritch Knight spells, Ranger favoured-enemy choices, Warlock invocations,
  class features, or conditional details for Athlete, Skilled, Ritual Caster, Spell
  Sniper, and Weapon Master.
- Root cause: the Windows catalog port created a generic subclass/spell/feat skeleton
  and only added three class-specific choice groups. The WPF planner also ignored
  `RequiredSelection`, so unavailable conditional choices were visible and the
  controller accepted them.
- Fix: preserve the existing model and add the live mac class features,
  class-specific choice groups, and same-level conditional feat groups for all 12
  classes. Centralize the mac prerequisite rule in `ManualBuildPlan`, filter WPF rows
  with it, and reject bypass attempts at the controller boundary. No local AI/backend
  behavior was imported.
- Regression tests: `EveryClassKeepsItsLiveMacFeaturesAndSpecialChoices`,
  `FeatsExposeEveryLiveMacConditionalChoice`,
  `ConditionalChoicesRequireTheReviewedSelectionScope`, the complete
  catalog/artwork inventory, and the isolated controller manual-build flow (including
  a rejected allocation before its feat is selected).
- Reviewer result: independent invalidation review pending.
- Residual risk: future mac catalog changes still require a reviewed Windows data
  update; generation was not introduced because that would expand architecture.

### WIN-PROD-002: batch leveling rewrote inactive roster plans

- Architecture: both.
- Severity: medium.
- Reproduction: initialize a run, record camp/unrecruited levels, call
  `SetAllPartyLevelsAsync(7)`, and observe every roster entry changed.
- Root cause: Windows iterated the normalized roster; live mac filters to
  `RosterStatus.Active`.
- Fix: skip non-active roster members.
- Regression test: all four active members become level 7 while every camp and
  unrecruited member retains the prior level.
- Reviewer result: independent invalidation review pending.
- Residual risk: none known.

### WIN-PROD-003: non-checkpoint route focus exposed an unrelated fight

- Architecture: both.
- Severity: high (wrong product guidance).
- Reproduction: focus a pending walkthrough step with no `checkpointId`; Windows
  returned the next recommended checkpoint and non-null readiness instead of the
  focused exploration/dialogue state.
- Root cause: `CurrentCheckpoint` fell through to route recommendation whenever the
  current step had no checkpoint. `CurrentStep` also omitted mac's earliest-active
  fallback when recommendation dependencies block every candidate.
- Fix: a current step now owns checkpoint selection (including explicit `null`), and
  current-step selection falls back to the earliest active step after the reviewed
  recommendation algorithm.
- Regression test: focused non-checkpoint exploration keeps `CurrentCheckpoint` and
  `Readiness` null.
- Reviewer result: independent invalidation review pending.
- Residual risk: packaged visual-state QA remains required.

### WIN-PROD-004: controller could complete a decision without an outcome

- Architecture: both.
- Severity: high (run-ledger integrity).
- Reproduction: focus any decision step and call `CompleteCurrentGoalAsync` directly;
  the UI normally avoids this call, but the controller recorded completion without a
  reviewed decision option.
- Root cause: the decision guard lived only in WPF event handlers.
- Fix: enforce the guard at the controller boundary; `ResolveOutcomeAsync` remains the
  only completion path and writes the selected outcome first.
- Regression test: direct completion returns false and remains pending; resolving the
  recommended option records the outcome and completes the step.
- Reviewer result: independent invalidation review pending.
- Residual risk: none known.

### WIN-PROD-005: loadout swaps and contested ownership were unreachable

- Architecture: both.
- Severity: medium.
- Reproduction: open an assigned character's Windows Loadout detail. Unlike live mac,
  there was no Change Pick/Revert flow and no contested-owner assignment control even
  though `PartyPlanningRules` already modeled both.
- Root cause: the initial Windows Loadout screen exposed targeting/equipping only.
- Fix: add validated controller commands for same-slot/current-act substitution and
  assignment override; expose Change Pick, Revert, and Party Conflict controls using
  the existing rules and shared item catalog.
- Regression test: isolated controller flow assigns the same build to two characters,
  persists the selected contested owner, substitutes a reviewed same-slot item, and
  reads the exact override back.
- Reviewer result: independent invalidation review pending.
- Residual risk: physical packaged keyboard/mouse/DPI usability review is required.

## Results and reflection

### Commands and results

- Environment measured 2026-07-26: Windows 11 Pro `10.0.26200`, OS architecture
  ARM64, ARM64 PowerShell, 8-byte pointers. The installed .NET 10.0.302 SDK/host is
  x64 (`win-x64`) and all local `dotnet build/test` execution is therefore explicitly
  labeled **x64-on-ARM64 emulated**. This is not native-x64 hardware evidence and is
  not native ARM64 product-process evidence.
- Locked Core restore: passed.
- Baseline Core build: failed with exactly two xUnit2031 errors, reproducing
  BG3-WIN-006.
- Final Core test build: passed, 0 warnings, 0 errors.
- Full Core suite: 164 passed, 0 failed. This includes shared artwork, all live mac
  class/feat choice representatives, run/route/party/build/loadout/act/gear rules,
  and serialization.
- App/product-flow test build: passed, 0 warnings, 0 errors; WPF XAML compilation
  validates the new Loadout controls and event routing.
- Focused `ProductFlowControllerTests`: 4 passed, 0 failed using unique per-test-class
  temporary SQLite state and the committed guide; no network or server was used.
- Architecture/native audit of owned model, route, serialization, controller, screen,
  and test files found no P/Invoke, native library, pointer-size, RID, x64, ARM64,
  AnyCPU, helper-process, localhost, gateway, or product-server dependency. Direct
  OpenRouter/credential implementation remains outside this lane and unchanged.

### Reflection and release gates

- The product-flow changes are managed and architecture-neutral. They add no helper,
  local model, local product server, paid API call, credential handling, injection,
  admin requirement, or player runtime.
- The live mac tree was read as the behavior oracle and not modified. Windows keeps
  the direct-OpenRouter/no-local-runtime product boundary.
- Still required outside this lane: independent reviewer invalidation, integrated
  arm64/x64 matrix execution, x64 Windows CI, native ARM64 packaged-product physical
  flow QA, and native-x64 physical validation as an explicit release gate.
