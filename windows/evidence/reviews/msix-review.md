# Independent MSIX packaging invalidation review

Reviewed commit: `b53008d212a09dd3c96c6ba9d034efc6c90eca93`

## Q/A before experiments

- Q: What is the main review hypothesis?
  - A: The packaging hardening may still accept a mislabeled or contaminated package at a parser, file-layout, or orchestration boundary even though its contract tests pass.
- Q: What evidence exists before this review?
  - A: The reviewed commit requires `arm64|x64`, substitutes a manifest architecture placeholder, selects MakeAppx by host OS architecture, parses PE machine/CLR metadata, validates before and after unpack, and enables the package test project. The worker reports synthetic ARM64 and AMD64 fixture coverage, but no independent invalidation result yet.
- Q: What remains unknown?
  - A: Whether unsupported PowerShell values fail before work begins; whether malformed placeholder variants or multiple identities/apps bypass validation; whether tool discovery selects the correct executable; whether malformed PE files are handled safely; whether mixed-mode, ReadyToRun, ARM64EC, ARM64X, x86 native, or unknown machines are correctly classified; whether the main host can be missing or duplicated; whether native SQLite/runtime contamination is rejected; whether pre/post-unpack validation examines equivalent content; whether temporary paths and cleanup are safe; and whether the test command proves a nonzero executed-test count.
- Q: What architecture claims may this review make?
  - A: WMI identifies this host as a Parallels ARM virtual machine on Apple Silicon. Synthetic parser/packaging results may be labeled native-ISA ARM64 VM packaging-tool evidence, not physical Windows ARM64 proof. An AMD64 payload or package handled here is not native-x64 hardware proof. No product install/runtime proof follows from synthetic fixtures.

## Adversarial acceptance tests

1. Inputs outside exactly `arm64` and `x64`, including omitted, `x86`, `AnyCPU`, `win-arm64`, whitespace, arrays, and ambiguous prefixes, fail before publish/package work.
2. Only the exact single source identity placeholder is accepted, and the produced manifest contains exactly the requested supported architecture.
3. Tool selection uses the native OS host architecture, rejects unsupported hosts, fails on missing tools, and does not silently accept an architecture-conflicting helper.
4. Truncated and malformed PE headers fail closed or are safely ignored without an out-of-bounds read.
5. Matching native app hosts pass; ARM64EC, ARM64X/hybrid, x86 native, conflicting AMD64/ARM64, and unknown machine values fail.
6. Managed x86 files are accepted only when they are genuinely architecture-neutral IL. Mixed-mode/native and ReadyToRun payloads must not receive a neutral-IL exemption.
7. The package fails if `BG3HonorAssistant.exe` is absent, managed, architecture-conflicting, or not the one native matching main host expected by the manifest. Multiple or shadowing host paths must not create ambiguity.
8. Cross-architecture SQLite, hostfxr/coreclr/runtime, or arbitrary nested native PE files fail regardless of filename or directory.
9. The same identity and PE invariants are checked before pack and after unpack, and the final copied artifact is the validated temporary package rather than an unchecked layout.
10. Temporary directories are unique, remain below the OS temporary root under boundary-aware path checks, are cleaned after success/failure, and cannot redirect validation/deletion through unsafe path or link behavior.
11. Package tests execute a nonzero count and assertions cannot be satisfied by mere source-string presence while behavior is bypassable.

## Results

The reviewed commit is **invalidated**. Its validator permits a real x86-only CLR
assembly in both ARM64 and AMD64 packages, and the contamination survives native
ARM64 MakeAppx pack/unpack with identical payload hashes. The current ten package
tests all pass despite this bypass.

## Evidence labels and host facts

- `Win32_ComputerSystem` reports `Parallels International GmbH.`, model
  `Parallels ARM Virtual Machine`, `SystemType=ARM64-based PC`, and
  `HypervisorPresent=True`. `Win32_Processor` reports `Apple Silicon`.
- Native Windows PowerShell 5.1 reports both OS and process architecture `Arm64`.
  ARM64 commands below are therefore **native-ISA ARM64 VM** evidence, not
  physical-Windows-ARM64 hardware proof.
- The restored MakeAppx host tools report ARM64, x64, and x86 respectively. The
  packaging script selected the ARM64 host tool on this VM, as intended.
- The available .NET 10.0.302 host reports architecture/RID `x64`/`win-x64`.
  Its test execution on this ARM64 VM is **emulated x64**, not native-x64 hardware
  proof.
- No native-x64 physical hardware evidence was produced. No product install,
  launch, process-architecture, or runtime behavior is claimed by this review.

The worker evidence in `windows/evidence/lanes/msix-packaging.md` repeatedly calls
this environment “physical ARM64.” That wording is unsupported and must be
corrected before integration.

## Findings

### MSIX-RV-001 — Critical — x86-only managed payloads pass both package architecture gates

- Architecture: ARM64 and x64.
- Reproduction:
  - `CustomMarshalers.dll` reports architecture `X86`.
  - An otherwise matching ARM64 layout incorrectly passed with that file present.
  - An otherwise matching x64 layout also incorrectly passed with that file present.
  - Native-ISA ARM64 VM MakeAppx pack and unpack returned `0` for both packages.
    Both post-unpack checks incorrectly passed, with zero missing or changed source
    payloads.
  - A separate malformed x86 managed-metadata fixture was also incorrectly
    accepted.
- Root cause: `Get-PePayload` treats any x86 PE with managed metadata as
  architecture-neutral IL. It does not validate the CLR portability flags or
  managed-native state needed to distinguish neutral IL from x86-only,
  mixed-mode, or ReadyToRun content.
- Required disposition: the worker must fix the classifier, add real x86-only and
  malformed CLR fixtures, and have a different reviewer rerun the pre/post-unpack
  cases for both target architectures. Merely checking a nonzero CLR directory is
  not an acceptable neutral-IL proof.
- Regression test currently present: none. The source-string contract test passes
  while this bypass remains.
- Reviewer result: reproducible invalidation for both target architectures at
  layout level and through native-ISA ARM64 VM MakeAppx pack/unpack.
- Residual risk: mixed-mode and ReadyToRun samples were not independently sourced
  in this lane. The reviewed code does not parse the metadata needed to classify
  them, so they remain unproven until covered by fixtures.

### MSIX-RV-002 — Medium — runtime validation accepts multiple packaged application hosts

- Architecture: ARM64 fixture; architecture-independent manifest behavior.
- Reproduction:
  - A full ARM64 manifest fixture with `BG3HonorAssistant.exe` plus
    `Secondary.exe` declared two packaged applications.
  - The pre-pack validator accepted it.
  - Native-ISA ARM64 VM MakeAppx pack and unpack both exited `0`.
  - The post-unpack validator accepted it and all source payload hashes matched.
- Root cause: `Assert-PackageLayout` inspects only identity architecture and PE
  files. It never asserts exactly one `Application`, that its executable is the
  root `BG3HonorAssistant.exe`, or that startup-extension executables agree.
- Existing mitigation: `ManifestTemplateRequiresExplicitSupportedWindowsDesktopArchitecture`
  currently calls `Assert.Single` on the checked-in source application, so the
  current template is guarded only when tests are run. The standalone packaging
  script and post-unpack gate do not enforce the invariant.
- Required disposition: either enforce the single exact main-host contract in the
  runtime package validator or explicitly document reliance on the separately run
  template test and preserve an executed-test-count gate in CI.
- Reviewer result: reproducible pre-pack, native-ISA ARM64 VM pack/unpack, and
  post-unpack acceptance.
- Residual risk: medium rather than high because the current checked-in template
  test would catch this specific manifest change in a correctly ordered CI matrix.

### MSIX-RV-003 — Medium — header-only pseudo-PE is reported as a native app host

- Architecture: ARM64 synthetic fixture; the parser behavior applies equally
  to AMD64.
- Reproduction: a structurally invalid matching-architecture synthetic
  `BG3HonorAssistant.exe` was incorrectly accepted and described as a native
  matching app host.
- Root cause: the parser is deliberately partial but the acceptance claim is
  stronger than the fields checked. MakeAppx packages files and is not an
  executable-load validator.
- Required disposition: either strengthen structural PE validation or narrow the
  claim and ensure packaged launch/process-architecture tests are a mandatory
  artifact gate.
- Reviewer result: reproducible validator bypass. The normal full package fixture
  used a real ARM64 SDK executable, so MSIX-RV-001 does not depend on this
  pseudo-PE behavior.
- Residual risk: trusted `dotnet publish` lowers likelihood, while a truncated or
  replaced app host would still produce a falsely “validated” artifact.

### MSIX-RV-004 — High evidence defect — ARM64 VM was described as physical hardware

- Architecture: ARM64 evidence provenance.
- Reproduction: compare the worker’s “physical ARM64” statements with
  `Win32_ComputerSystem` and `Win32_Processor` facts above.
- Root cause: OS/process ISA was conflated with hardware provenance.
- Required disposition: replace those claims with “native-ISA ARM64 VM” and keep
  physical Windows 11 ARM64 validation open as a release gate.
- Reviewer result: invalidated by WMI evidence.
- Residual risk: this lane cannot satisfy the user’s required physical ARM64 QA.

## Adversarial matrix

The disposable harness was created only for this review, executed from native
ARM64 Windows PowerShell, and removed afterward. Its 18 layout cases produced 13
expected results and five deliberately expected rejections that the current
validator instead accepted.

| Case | Expected | Actual | Review |
|---|---:|---:|---|
| Matching ARM64 host | accept | accept | verified |
| Matching AMD64 host | accept | accept | synthetic packaging-only |
| AMD64 `e_sqlite3.dll` in ARM64 | reject | reject | verified |
| ARM64 `coreclr.dll` in AMD64 | reject | reject | verified |
| ARM64EC payload | reject | reject | verified |
| ARM64X payload | reject | reject | verified as unknown/conflicting |
| Native x86 without managed metadata | reject | reject | verified |
| Unknown machine payload | reject | reject | verified |
| Real CLR x86-only DLL in ARM64 | reject | **accept** | MSIX-RV-001 |
| Real CLR x86-only DLL in AMD64 | reject | **accept** | MSIX-RV-001 |
| Malformed x86 managed-metadata fixture | reject | **accept** | MSIX-RV-001 |
| Missing main host | reject | reject | fails closed |
| Managed/x86 main host | reject | reject | verified |
| Truncated non-PE nested file | ignore | ignore | bounds-safe |
| Malformed PE offset | reject | reject | bounds-safe |
| Truncated optional header | reject | reject | bounds-safe |
| Header-only main executable | reject | **accept** | MSIX-RV-003 |
| Nested duplicate app-host filename | reject | **accept** | weak signal; full multi-app reproduction is MSIX-RV-002 |

Matching-machine ReadyToRun/native images are allowed by machine value, while a
conflicting ARM64/AMD64 ReadyToRun image is rejected before the managed exemption.
The unresolved case is x86 managed content because the current code does not read
the CLR portability flags or managed-native header.

## Other acceptance-test results

### Inputs and manifest substitution

- Actual script invocations with the architecture omitted or set to `x86`,
  `AnyCPU`, `win-arm64`, whitespace-padded `arm64`, ambiguous `a`, or literal
  `arm64,x64` all exited `1` during parameter binding. No exact
  `BG3HonorAssistant-msix-<32 hex>` temporary directory remained.
- The checked-in manifest contains one exact
  `ARCHITECTURE_PLACEHOLDER`; the script rejects any other source identity value
  before substitution. The enabled template test also asserts a single identity.
- PowerShell `ValidateSet` is case-insensitive; case variants of the two supported
  values were not run through the full isolated script because this commit’s
  `build-release.ps1` dependency has not yet integrated the matching
  `-Architecture` parameter. The coordinator must test canonical artifact naming
  after integrating the build/RID lane.

### Host-tool selection

- The NuGet SDK build-tools directory contains exactly one MakeAppx per `arm64`,
  `x64`, and `x86` host subdirectory for the pinned version.
- On the ARM64 VM, the reviewed selection resolves the native ARM64
  `MakeAppx.exe`. That native tool successfully packed both ARM64-target and
  x64-target synthetic MSIX packages; no x64-only helper was required.
- Unsupported OS architecture and missing-tool behavior were inspected as
  fail-closed branches but could not be induced without falsifying host state or
  the restored dependency cache.

### Pre/post unpack equivalence

- Three full fixtures were packed and unpacked: ARM64 plus x86-managed
  contamination, x64 plus x86-managed contamination, and an ARM64 two-application
  manifest. All returned pack/unpack exit `0`, passed the same validator both
  times, and had zero missing/changed source payload hashes.
- This verifies that MakeAppx preserved the inspected payloads. It also proves that
  re-running an incomplete invariant after unpack cannot repair the invariant.
- These are synthetic packaging fixtures, not BG3 Honor Assistant builds,
  installs, launches, or runtime tests.

### Temporary/path safety

- The reviewed script derives a unique root below the OS temporary directory,
  derives publish/inspection paths beneath it, and removes it from `finally`.
- After failure-input and harness runs there were zero exact product temporary
  roots and zero independent-review temporary roots.
- The path checks are not fully canonical, but no temporary path escape was
  reproduced with the in-repository publish producer.
- No final artifact path escape was reproduced.

### Zero-test false green

- Locked restore passed.
- `dotnet test ... --configuration Release --no-restore` executed a nonzero suite:
  `Failed: 0, Passed: 10, Skipped: 0, Total: 10`.
- The earlier zero-test defect is fixed. However,
  `DevelopmentMsixBuildValidatesBothArchitectureSpecificPackages` is a
  source-string contract test rather than a behavioral validator test. All ten
  tests are green while MSIX-RV-001 through MSIX-RV-003 reproduce, so the current
  suite is not a sufficient packaging gate.
- This test run used an x64 .NET host under ARM64 VM emulation and is labeled
  **emulated x64**.

## Reviewer conclusion

Do not accept or integrate `b53008d212a09dd3c96c6ba9d034efc6c90eca93` as
architecture-clean until MSIX-RV-001 is fixed and independently re-reviewed.
MSIX-RV-002 and MSIX-RV-003 need explicit disposition. The worker's ARM64 evidence
provenance must be corrected, and physical Windows 11 ARM64 remains untested by
this environment. Native-x64 physical validation likewise remains an explicit
release gate.
