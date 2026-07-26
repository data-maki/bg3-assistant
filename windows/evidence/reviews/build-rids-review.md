# Independent build and RID invalidation review

Reviewed commit: `e6678bab400c833bce09870c0a0f47c1b4e5bc05`

## Q/A before experiments

- Q: What is the main hypothesis?
  - A: The architecture hardening may appear correct for its documented commands while MSBuild property precedence, solution mapping, restore graphs, testhost selection, CI host setup, artifact reuse, or incomplete native-file inspection still permits a mislabeled, cross-architecture, or unexecuted build to report green.
- Q: What evidence exists before this review?
  - A: The commit adds explicit architecture properties, solution mappings, locked dependency files, ARM64/x64 CI jobs, architecture inspection, architecture-specific release publishing, and lane evidence. The worker reports local ARM64 cross-builds and emulated x64 test runs, but no independent invalidation result.
- Q: What remains unknown?
  - A: How missing, invalid, and conflicting `BG3Architecture`, `RuntimeIdentifier`, `RuntimeIdentifiers`, `Platform`, and `PlatformTarget` values resolve at project and solution entrypoints; whether Visual Studio and SLNX mappings carry the intended value; whether both locked RID graphs restore; whether tests actually run in a target-matching process; whether ARM CI installs a matching .NET host; whether output paths collide; whether every PE/native asset and deps/runtime entry is inspected; whether interop and SQLite assets are present; whether CI syntax, runner labels, test counts, `global.json`, `PATH`, script working directories, and package artifacts are reliable.
- Q: What evidence labels apply?
  - A: This environment is a Parallels ARM virtual machine on Apple Silicon. Native Windows PowerShell is native-ISA ARM64 VM evidence, the installed x64 .NET host is emulated x64, ARM64 publish from an x64 host is cross-build evidence, and x64 GitHub execution must be labeled x64 CI. Neither this environment nor GitHub CI is native-x64 physical hardware proof. Physical ARM64 and native-x64 hardware remain separate release gates.

## Adversarial acceptance tests

1. Exactly `arm64` and `x64` are supported; missing, invalid, whitespace, list, and contradictory architecture properties fail before meaningful build work.
2. `BG3Architecture`, `RuntimeIdentifier`, `RuntimeIdentifiers`, `Platform`, and `PlatformTarget` cannot disagree silently at project or solution entrypoints.
3. SLNX configurations and Visual Studio/MSBuild solution invocations map ARM64 and x64 to the intended project architecture without falling back to AnyCPU or a host-derived RID.
4. Locked restore succeeds independently for both supported RID graphs and fails when a required lock graph is absent or changed.
5. Test evidence proves target testhost process architecture and a nonzero executed count; OS architecture alone is not accepted.
6. ARM CI uses a native ARM64 .NET host and records process architecture; x64 CI records an x64 process. Runner labels alone are insufficient.
7. ARM64 and x64 builds, publishes, tests, packages, logs, and evidence use collision-free architecture-specific paths and names.
8. Architecture inspection enumerates every PE recursively and checks deps/runtime metadata, rather than validating only a fixed filename list.
9. Cross-architecture native SQLite, Windows App SDK, hostfxr/coreclr, ReadyToRun, interop, or other runtime assets are rejected; required architecture-specific assets are present.
10. Workflow syntax, runner labels, matrix expressions, paths, test-count gates, and package publication are internally consistent.
11. `global.json`, .NET installation paths, `PATH`, current directory, and script-relative project/output resolution are deterministic from repository root and supported subdirectories.

## Results

The reviewed commit is **invalidated**. Locked restores and architecture-specific
publishes work for both target RIDs, but the MSBuild validation can be made
self-consistent around caller-overridden invariant properties, the architecture
inspector ignores unlisted PE files, the solution platform is not sufficient to
select an architecture, and CI does not prove either its .NET/testhost process
architecture or a nonzero test count. The workflow also calls a packaging
interface that does not exist in this isolated commit.

## Evidence labels and host facts

- `Win32_ComputerSystem` identifies this environment as a Parallels ARM virtual
  machine on Apple Silicon. Native Windows PowerShell reports OS and process
  architecture `Arm64`. This is **native-ISA ARM64 VM** evidence, not physical
  Windows ARM64 hardware proof.
- `dotnet --info` reports SDK 10.0.302, host architecture `x64`, and RID
  `win-x64`. Local .NET build/test commands are therefore **emulated x64** on the
  ARM64 VM.
- The ARM64 publish was produced by that x64 SDK and is labeled **ARM64
  cross-build**. Its architecture inspector ran in native-ISA ARM64 PowerShell,
  but no ARM64 product or testhost process was executed.
- No GitHub job was run from this branch. `windows-latest` remains intended
  **x64 CI** evidence and `windows-11-arm` remains intended ARM64 CI evidence.
  Runner labels are accepted as current, but neither is physical hardware proof.
- Physical Windows 11 ARM64 QA and native-x64 physical validation remain open
  release gates.

## Findings

### BUILD-RV-001 — Critical — unlisted native PE files bypass architecture inspection

- Architecture: ARM64 contamination in an x64 publish; applies symmetrically.
- Reproduction:
  - A clean `win-x64` self-contained publish passed
    `inspect-architecture.ps1`.
  - An ARM64 PE was then added as `unlisted-native.dll`.
  - The x64 inspector again returned exit `0` and `"result": "pass"`.
  - The temporary file was removed after the result was recorded.
- Root cause: `Assert-PublishLayout` checks the app host plus a fixed list of
  eleven native payload names. It does not recursively classify every PE.
- Coverage evidence: the actual x64 publish contains 488 PE files. Of 168
  matching-machine files, 156 are not in the fixed list. Those include
  ReadyToRun managed images and native files such as `clrjit.dll`, `clrgc.dll`,
  `D3DCompiler_47_cor3.dll`, `Microsoft.DiaSymReader.Native.amd64.dll`,
  `msquic.dll`, `PenImc_cor3.dll`, and `System.IO.Compression.Native.dll`.
- Deps/runtime gap: the inspector checks only the suffix of
  `deps.runtimeTarget.name`; it does not reconcile the dependency graph's native
  and runtime-target assets with the files on disk.
- Reviewer result: reproducible invalidation; a cross-architecture unlisted PE is
  accepted in a publish that reports pass.
- Required disposition: recursively enumerate/classify every PE and validate
  deps/runtime assets. A different reviewer must repeat unlisted native,
  ReadyToRun, managed-neutral, SQLite, and malformed-PE cases for both RIDs.
- Residual risk: the separate packaging review found a distinct managed-x86
  classification issue. The final build and package validators need one
  consistent PE policy.

### BUILD-RV-002 — High — caller-controlled properties defeat the intended MSBuild invariants

- Architecture: ARM64 and x64.
- Reproduction:
  - Normal direct validation passed for `BG3Architecture=arm64`.
  - Missing architecture, `x86`, a conflicting RID, conflicting `Platform`,
    conflicting `PlatformTarget`, and a reordered RID list all failed as
    intended.
  - Setting `BG3Architecture=arm64` while overriding both
    `BG3ExpectedRuntimeIdentifier` and `RuntimeIdentifier` to x64 caused
    `ValidateBG3Architecture` to return exit `0`.
  - Overriding both `BG3SupportedRuntimeIdentifiers` and `RuntimeIdentifiers` to
    an ARM64-only list also returned exit `0`, despite the stated exact
    two-RID invariant.
- Root cause: the expected RID and supported-RID list are ordinary global
  MSBuild properties. The validation compares caller-controlled values with
  other caller-controlled values, so a caller can change both sides.
- Reviewer result: two direct invalidations in the actual validation target.
- Required disposition: derive invariants in non-overridable target items or
  compare directly with literals, then add negative build/restore tests that try
  to override every helper property.
- Residual risk: the .NET SDK independently rejects some executable
  RID/PlatformTarget contradictions. That secondary check does not protect the
  supported-RID graph and should not be treated as proof that the custom
  invariant is sound.

### BUILD-RV-003 — High — ARM CI verifies OS ISA but not .NET or testhost ISA

- Architecture: ARM64 CI.
- Reproduction/evidence:
  - The workflow accepts the ARM job when
    `RuntimeInformation.OSArchitecture == Arm64`, then only prints
    `dotnet --info`.
  - This review environment has exactly that split: OS and PowerShell are ARM64
    while the selected `dotnet` host is x64. The workflow's OS check would pass
    without proving an ARM64 .NET process.
  - Test TRX files do not provide a gated expected process architecture. One
    controlled-window test logs process architecture, but CI never asserts that
    output and other test projects do not provide the proof.
  - The official
    [`actions/setup-dotnet@v4` action metadata](https://github.com/actions/setup-dotnet/blob/v4/action.yml)
    exposes no architecture input.
- Root cause: runner architecture, .NET host architecture, build target
  architecture, and testhost process architecture are treated as one fact.
- Reviewer result: evidence gate invalidated by a locally demonstrated
  ARM64-OS/x64-dotnet combination. No claim is made that the hosted ARM runner
  will choose x64; the defect is that the workflow would not reject or clearly
  classify it.
- Required disposition: assert and record the `dotnet` process architecture and
  add a test executed inside each testhost that compares
  `ProcessArchitecture` with the matrix target.
- Residual risk: a correct ARM64 hosted run may pass once added, but it has not
  run on this branch.

### BUILD-RV-004 — High — CI can report green after executing zero tests

- Architecture: ARM64 and x64 CI.
- Reproduction:
  - `dotnet test` was invoked with `IsTestProject=false` against the package test
    project.
  - It returned exit `0`, emitted zero output lines, and reported no test count.
  - The workflow checks only `$LASTEXITCODE`.
- Root cause: CI neither asserts `IsTestProject` for every discovered project nor
  parses TRX counters to require a nonzero executed count. Artifact upload can
  still succeed because the same upload contains MSIX and JSON files; it does not
  require each path pattern to match.
- Reviewer result: reproducible zero-test false green at the command contract
  used by the loop.
- Required disposition: fail when no test projects are discovered, require each
  invocation to produce one expected TRX, and parse counters for a positive
  executed total.
- Residual risk: the build-lane TRXs prove tests ran in prior local commands, but
  they do not make the proposed CI gate safe against future project/configuration
  changes.

### BUILD-RV-005 — High integration blocker — workflow calls a packaging contract absent from this commit

- Architecture: ARM64 and x64 CI.
- Reproduction: compare `.github/workflows/ci.yml` with
  `tools/build-development-msix.ps1` in the reviewed commit. The workflow passes
  `-Architecture`, but the script has no such parameter, publishes x64, selects
  x64 MakeAppx, emits an x64 artifact name, and the source manifest/test still
  require x64.
- Root cause: the build/RID workflow was committed before its packaging-lane
  dependency. The CI file nevertheless presents the combined job as executable.
- Reviewer result: deterministic failure/incorrect-target contract in this
  isolated commit; the workflow has not run.
- Required disposition: integrate the independently reviewed packaging change
  before treating the workflow as testable, then run both jobs. The packaging
  review's critical findings must be fixed before integration.
- Residual risk: this is an expected cross-lane dependency, not a reason to
  duplicate packaging changes in the build lane.

### BUILD-RV-006 — Medium — exposed solution platforms do not select BG3Architecture

- Architecture: ARM64 and x64 Visual Studio/SLNX entrypoints.
- Reproduction:
  - `BG3HonorAssistant.slnx` exposes `arm64` and `x64` solution platforms and maps
    each project platform.
  - Building the solution with `Platform=arm64` and no hidden
    `BG3Architecture` failed all projects because `BG3Architecture` was missing;
    the app also reported an x64 RID versus ARM64 PlatformTarget conflict.
- Root cause: `Directory.Solution.props` maps `BG3Architecture` to `Platform` in
  one direction only. Selecting the architecture shown by Visual Studio does not
  set the required build input.
- Reviewer result: reproducible solution-entrypoint failure.
- Required disposition: either make solution platform the explicit input for
  solution/Visual Studio builds or expose a supported way for Visual Studio to
  set `BG3Architecture`, with automated solution-entrypoint tests.
- Residual risk: command-line solution builds that explicitly pass
  `BG3Architecture` map as intended.

### BUILD-RV-007 — Medium — setup-dotnet is not pinned to windows/global.json

- Architecture: ARM64 and x64 CI reproducibility.
- Reproduction/evidence:
  - The repository pins SDK `10.0.302` with `rollForward=latestPatch` in
    `windows/global.json`.
  - `actions/setup-dotnet@v4` runs from the repository action context with
    `dotnet-version: 10.0.x`; run-step `working-directory: windows` does not apply
    to `uses` steps.
  - The action supports `global-json-file` for a non-root file, but the workflow
    does not set it. The broad channel and the pinned feature band can therefore
    diverge as .NET 10 servicing advances.
- Root cause: SDK installation and SDK selection use separate version contracts.
- Reviewer result: static reproducibility invalidation against the official
  action inputs; no GitHub run was available.
- Required disposition: install from `windows/global.json` and assert the
  selected SDK version and process architecture before restore.
- Residual risk: it works locally because 10.0.302 is installed. Hosted runner
  image contents are not a reproducible substitute.

## Acceptance-test results

| Area | Result | Evidence label |
|---|---|---|
| Missing/invalid direct architecture input | Pass | Missing and x86 rejected |
| Direct RID/Platform/PlatformTarget mismatch | Pass for ordinary inputs | Caller override invalidations remain |
| Exact two-RID helper invariant | Fail | BUILD-RV-002 |
| SLNX explicit `BG3Architecture` mapping | Pass per worker/local outputs | Command-line contract |
| SLNX/Visual Studio platform-only selection | Fail | BUILD-RV-006 |
| Locked solution restore, ARM64 | Pass, 11 projects | Emulated x64 SDK resolving ARM64 graph |
| Locked solution restore, x64 | Pass, 11 projects | Emulated x64 |
| Lock target inventory | Pass | All 11 locks contain base, win-arm64, and win-x64 targets |
| ARM64 self-contained publish | Pass | ARM64 cross-build |
| x64 self-contained publish | Pass | Emulated x64 build |
| Default publish path isolation | Pass | `artifacts/publish/win-arm64` and `win-x64` |
| Publish deps target | Pass | Exact win-arm64/win-x64 suffixes |
| SQLite presence/architecture | Pass | `e_sqlite3.dll` is ARM64/x64 respectively |
| Recursive PE contamination | Fail | BUILD-RV-001 |
| ARM CI .NET/testhost proof | Fail | BUILD-RV-003 |
| Nonzero test gate | Fail | BUILD-RV-004 |
| Workflow/package interface | Fail until integration | BUILD-RV-005 |
| Workflow syntax/runner labels | Labels accepted; workflow not run | No CI proof |
| Script cwd and default output | Pass | Script resolves project from its own root and pushes `windows` |
| PATH/global.json reproducibility | Partial | BUILD-RV-007 |

The two publishes contain separate dependency targets and architecture-correct
SQLite files. ARM64 has 1,255 files and x64 has 1,256 files; no default-path
collision was observed. A caller can still direct both release invocations to one
custom `OutputPath`, so matrix orchestration must keep explicit per-RID paths.

## Test execution disposition

The build worker's checked-in emulated-x64 TRXs contain nonzero tests, but the
recorded suites are not green: App 8 pass/8 fail, Infrastructure 74 pass/2 fail,
Package 0 pass/9 fail, Windows 35 pass/2 fail, and Core 159 pass/1 fail under its
warning override. The normal solution build is also blocked by existing
warnings-as-errors. Those results are useful defect evidence, not a green x64
matrix claim.

No ARM64 testhost was executed in this review. No x64 GitHub runner was used.
Therefore this lane supplies ARM64 cross-build, native-ISA ARM64 VM inspection,
and emulated-x64 evidence only.

## Reviewer conclusion

Do not accept `e6678bab400c833bce09870c0a0f47c1b4e5bc05` as an
architecture-clean, green build matrix until BUILD-RV-001 through BUILD-RV-005
are fixed or integrated and independently rerun. BUILD-RV-006 and BUILD-RV-007
need explicit disposition. Physical Windows 11 ARM64 QA and native-x64 physical
validation remain release gates and must not be inferred from CI or this VM.
