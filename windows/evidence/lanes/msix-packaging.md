# MSIX packaging lane

## Q/A before implementation

- Hypothesis: the development MSIX path is x64-hard-coded in its manifest, output name, publish invocation, SDK-tool selection, and tests, so an ARM64 invocation would either create an incorrectly labeled package or silently package x64 payloads.
- Evidence at start: `Package.appxmanifest` declares `ProcessorArchitecture="x64"`; `build-development-msix.ps1` emits an `_x64_` filename, selects only an `x64\makeappx.exe`, calls `build-release.ps1` without an architecture input, and does not inspect packaged PE/native assets; `PackageManifestTests` asserts only x64.
- Unknowns: whether the release publisher already accepts explicit architecture/RID inputs; which Windows SDK MakeAppx host binaries are restored; whether self-contained publish output contains architecture-specific native files that need direct inspection; whether package extraction tools are present in this environment.
- Acceptance tests:
  - The packaging command requires exactly `arm64` or `x64` and maps those to exactly `win-arm64` or `win-x64`.
  - Each package has a matching architecture-specific filename and manifest identity; source/template state is not neutral/AnyCPU.
  - Packaging invokes a self-contained publish for the matching RID and rejects PE/native payloads whose machine architecture conflicts with the requested package.
  - Each `.msix` is unpacked/inspected after creation before it is copied to final artifacts.
  - Unsupported or neutral architecture inputs fail deterministically.
  - Package-focused tests cover both supported architectures and the rejection paths.
  - Cross-build/package inspection is reported only as build-time evidence, never as native runtime proof.

## Cross-lane contract

The coordinator confirmed that both packaging and release scripts use
`-Architecture arm64|x64`; packaging derives `win-$Architecture` and passes the same
architecture plus an explicit output path to `build-release.ps1`. The build/RID lane
owns the corresponding release-script implementation.

## Findings and dispositions

### PKG-001 — High — architecture label and payload selection were independent

- Architecture: ARM64 and x64.
- Reproduction: inspect `Package.appxmanifest` and
  `build-development-msix.ps1`; the manifest, artifact name, SDK-tool path, and
  publish path were all independently fixed to x64, and there was no architecture
  parameter.
- Root cause: the initial one-architecture implementation encoded x64 at each
  packaging layer instead of carrying one validated build input through publish,
  manifest generation, validation, and artifact naming.
- Fix: require `-Architecture arm64|x64`, derive `win-$Architecture`, pass the
  architecture to the release publisher, replace a manifest-only placeholder at
  package time, and emit architecture-specific artifact names.
- Regression test: `ManifestTemplateRequiresExplicitSupportedWindowsDesktopArchitecture`
  and `DevelopmentMsixBuildValidatesBothArchitectureSpecificPackages`.
- Reviewer result: architecture-binding behavior was not invalidated; integrated
  product-package review remains with the coordinator.
- Residual risk: the product MSIX matrix requires integration with the build/RID
  lane before the complete application payload can be built.

### PKG-002 — Critical — packaging did not reject cross-architecture native payloads

- Architecture: ARM64 and x64.
- Reproduction: the original script copied all publish output into an MSIX after
  changing only version/publisher; it never inspected PE machine fields or unpacked
  the created MSIX.
- Root cause: successful MakeAppx creation was treated as payload validation even
  though MakeAppx does not establish that each native file matches the identity
  architecture.
- Fix: parse every PE, allow only matching ARM64 (`0xAA64`) or AMD64 (`0x8664`)
  native payloads, and allow `0x014C` only after its CLI directory and header map
  in-bounds through exactly one section, its metadata maps in-bounds with a `BSJB`
  signature, CorFlags prove IL-only without 32-bit-required/preferred or native
  entry point, and it has no managed-native/ReadyToRun header. Reject ARM64EC,
  malformed CLR metadata, mixed-mode/native i386, and every other
  conflicting/unknown machine. Require the main executable to be a native matching
  app host, require exactly one manifest Application and consistent exact executable
  references, then unpack and re-run the same validation before copying the artifact.
- Regression test: executable validator tests cover a real framework x86
  `CustomMarshalers.dll`, neutral x86-machine IL, 32BITREQUIRED,
  32BITPREFERRED, mixed-mode, native entry point, managed-native/ReadyToRun header,
  forged metadata, the reviewer’s inconsistent CLI RVA/size bypass, additional
  Application entries, and mismatched executable references.
- Reviewer result: the independent reviewer invalidated the first fix.
  `C:\Windows\Microsoft.NET\Framework\v4.0.30319\CustomMarshalers.dll`
  (i386 CLR, X86) passed an ARM64 layout because the old rule treated any nonzero
  CLR RVA as managed neutral IL. A synthetic i386 PE with CLI RVA 1 and size 0 also
  passed without a valid CLI header. Both reproductions fail with the follow-up
  validator and are now regression-tested.
- Residual risk: exotic non-PE native formats would require a separately justified
  rule; current Windows self-contained outputs are expected to use PE native assets.

### PKG-003 — High — ARM64 packaging depended on an x64-only helper

- Architecture: native ARM64.
- Reproduction: the original MakeAppx lookup selected only
  `\x64\makeappx.exe` even though the restored SDK package also contains an ARM64
  host tool.
- Root cause: package target architecture was conflated with packaging-tool host
  architecture.
- Fix: select MakeAppx from the operating-system architecture (`arm64` on ARM64,
  `x64` on x64) and reject other tool hosts. Package target architecture remains a
  separate input.
- Regression test: package-script contract test; the synthetic pack/unpack exercise
  ran the restored ARM64 MakeAppx host.
- Reviewer result: the helper-host finding was not invalidated; integrated review
  remains with the coordinator.
- Residual risk: none known for supported ARM64/x64 Windows hosts.

### PKG-004 — High — package tests reported success while running zero tests

- Architecture: test-infrastructure defect affecting both targets.
- Reproduction: before the fix,
  `dotnet test windows/tests/BG3HonorAssistant.Package.Tests/BG3HonorAssistant.Package.Tests.csproj --no-restore`
  exited 0 with no test count; diagnostic output said the project lacked
  `IsTestProject`. After enabling it, all tests initially failed to find the repo in
  this worktree, and three source checks referenced pre-refactor paths.
- Root cause: the project was not marked as a test project; its repo discovery
  depended on a visible `.git` directory, and app-surface checks were not updated
  after XAML/Tray files moved.
- Fix: set `IsTestProject=true`, discover the repo through stable checked-in files,
  update the tray path, and aggregate all app XAML so the checks cover split screens.
- Regression test: the command now reports `Passed: 10, Failed: 0, Skipped: 0`.
- Reviewer result: executed tests exposed the validator bypass and now include its
  deterministic regressions; integrated review remains with the coordinator.
- Residual risk: none known.

## Lane-local verification

Host facts for this lane:

- Native-ISA OS architecture reported by Windows PowerShell inside the Windows 11
  ARM64 Parallels VM: `RuntimeInformation.OSArchitecture = Arm64`.
- The installed .NET SDK/host used for x64 test execution reports `Architecture:
  x64`; on this ARM64 host that is emulated x64, not native-x64 hardware evidence.
- No native-x64 hardware claim is made.

Commands and results:

1. PowerShell parser plus `git diff --check`:
   `Parser.ParseFile(windows/tools/build-development-msix.ps1, ...)` returned no
   parse errors; `git diff --check` returned 0 (line-ending conversion warnings only).
2. Locked restore:
   `dotnet restore windows/tests/BG3HonorAssistant.Package.Tests/BG3HonorAssistant.Package.Tests.csproj --locked-mode`
   passed.
3. Package tests:
   `dotnet test windows/tests/BG3HonorAssistant.Package.Tests/BG3HonorAssistant.Package.Tests.csproj --configuration Release --no-restore`
   passed 14/14, skipped 0 after the reviewer follow-up.
4. Rejection input:
   `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File windows/tools/build-development-msix.ps1 -Architecture x86`
   failed during parameter binding because x86 is outside `arm64,x64`.
5. Synthetic validator exercise in the native-ISA ARM64 Windows 11 Parallels VM:
   the validator functions were parsed from the packaging script; an ARM64 native
   fixture (`0xAA64`) and an AMD64 native fixture (`0x8664`) each passed layout
   validation, ARM64 MakeAppx pack, ARM64 MakeAppx unpack, and post-unpack
   validation. Adding the AMD64 fixture to the ARM64 layout failed with
   `Cross-architecture PE payload ... machine 0x8664; expected ARM64`.
6. Reviewer follow-up validator exercise:
   the real framework `CustomMarshalers.dll` x86 assembly and deterministic
   malformed/mixed/native fixtures were rejected; neutral IL passed. The native
   ARM64 MakeAppx host then packed and unpacked both matching ARM64 and AMD64
   fixtures, with the hardened validator passing both before packing and after
   unpacking. To reproduce the reviewer path exactly, native ARM64 MakeAppx was also
   allowed to pack the deliberately contaminated ARM64 fixture without the normal
   pre-pack gate; the hardened validator rejected the real x86 assembly both before
   packing and after unpacking (exit 1 in each position).

The synthetic fixtures prove packaging inspection/tool behavior only. They are not
BG3 Honor Assistant product builds, installation tests, or runtime proof. Full
self-contained product MSIX construction for both RIDs is deliberately deferred to
the coordinator’s integrated build/RID + packaging matrix.

## Reflection

The useful invariant is not just that the manifest and filename agree: publish RID,
main app host, every native payload, unpacked MSIX identity, and artifact label must
all agree before an artifact leaves temporary storage. Running the previously
dormant tests also demonstrated why an explicit executed-test count belongs in the
matrix rather than relying on a successful `dotnet test` exit code.
