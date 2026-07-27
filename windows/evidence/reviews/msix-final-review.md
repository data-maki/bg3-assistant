# Final independent MSIX validator review

Reviewed follow-up: `9859fb6`

## Q/A before experiments

- **Hypothesis:** the follow-up may close the three residual findings in its
  synthetic fixtures while still accepting a non-launchable main host, selecting
  a deceptive foreign-namespace `Application`, rejecting a valid native image
  with a short data-directory table, or regressing earlier x86/malformed/
  multi-application contamination rejection.
- **Evidence available:** prior independent review `0a1c153` left three residuals:
  incomplete main-host launchability proof, namespace-agnostic Application
  selection, and false rejection of native images with fewer than fifteen data
  directories. Commit `9859fb6` adds PE entry-point/characteristic checks, exact
  foundation-namespace selection, foreign-namespace rejection, short-table
  handling, and focused behavioral fixtures.
- **Unknowns:** whether entry points must map to exactly one executable,
  file-backed section; whether PE32, DLL, missing/unmapped entry points and invalid
  subsystems fail; whether alternate XML prefixes for the exact foundation
  namespace pass while foreign namespaces fail; whether prior x86 managed,
  malformed CLR, opposing-machine, and multi-application cases still fail both
  before packing and after unpacking; and whether native ARM64 MakeAppx remains
  available.
- **Acceptance tests:** execute nonzero focused tests for launchable and malformed
  main-host PE structure, exact foundation namespace and deceptive foreign
  namespace, short `NumberOfRvaAndSizes`, and representative earlier x86,
  malformed-CLR, opposing-machine, mismatched/multiple-application contamination.
  If feasible, run clean and contaminated native ARM64 MakeAppx pre-pack and
  post-unpack checks. Accept only if all three residuals close without weakening
  earlier fail-closed behavior.
- **Evidence label:** this machine is a Windows 11 ARM64 Parallels VM on Apple
  Silicon. Native ARM64 PowerShell/MakeAppx is **native-ISA ARM64 VM
  packaging-only** evidence, not physical ARM64 runtime proof. The installed x64
  .NET host is **x64-on-ARM64 emulated**, not native-x64 hardware proof.

## Results

### Environment and execution labels

- Windows `10.0.26200` reported OS architecture ARM64; native Windows
  PowerShell reported ARM64.
- `Win32_ComputerSystem` reported `Parallels ARM Virtual Machine`,
  `Parallels International GmbH.`, and `HypervisorPresent=True`.
- The installed .NET 10.0.302 SDK/10.0.10 test host reported x64 and RID
  `win-x64`. The xUnit driver was therefore **x64-on-ARM64 emulated**.
- The tests deliberately resolve `Sysnative` from the x64 driver and execute the
  package validator with native Windows PowerShell. Validator execution is
  therefore **native-ISA ARM64 VM packaging-only** evidence.
- Restored MakeAppx
  `10.0.28000.2270\...\arm64\makeappx.exe` read as PE machine `0xAA64`
  and launched its help surface. This proves the native ARM64 tool host was
  available, not that a product MSIX was installed or launched.

### Commands and focused outcomes

1. Locked restore of
   `BG3HonorAssistant.Package.Tests.csproj`: passed.
2. Focused
   `FullyQualifiedName~PackageArchitectureValidationTests` run in Release:
   **6 passed, 0 failed, 0 skipped** in 4 minutes 41 seconds.
3. `MainExecutableRequiresLaunchableNativeHostStructure`: passed all rejection
   cases for PE32, missing entry point, unmapped entry point, non-executable
   entry-point section, and DLL image while retaining the valid PE32+ native
   fixture.
4. `ValidNativePeWithShortDataDirectoryTableIsAccepted`: passed for a matching
   native PE with zero declared directories and a compact valid optional header.
5. `ManifestRejectsAdditionalOrForeignApplicationAndExecutableReferences` and
   `ManifestRejectsMismatchedApplicationExecutable`: passed for an extra
   foundation Application, a deceptive foreign-namespace Application, a foreign
   executable reference, and a mismatched product executable.
6. `NeutralIlIsAcceptedButRealX86ManagedAssemblyIsRejected`: accepted real
   architecture-neutral IL and rejected the real framework x86 managed assembly.
7. `I386ClrBypassesAreRejected`: rejected representative prior contamination:
   32-bit-required, 32-bit-preferred, mixed mode, native entry point,
   managed-native/ReadyToRun, forged metadata, and malformed CLI directory.

### Independent code review

- The main-host gate now requires the matching native machine, PE32+, COFF
  executable-image and non-DLL characteristics, a Windows GUI/CUI subsystem, a
  nonzero entry point, and exactly one executable file-backed section containing
  that entry point. This directly addresses the launchability structure that
  `0a1c153` found absent.
- The manifest XPath now selects exactly
  `/foundation:Package/foundation:Applications/foundation:Application` through
  the foundation namespace URI. XML prefixes are aliases, so a different prefix
  bound to the exact foundation URI remains valid. A second local-name scan
  rejects a same-named element from any foreign namespace.
- `NumberOfRvaAndSizes` is read before requiring a CLI directory. Fewer than
  fifteen directories classify a matching PE as native; fifteen or more still
  require the CLI entry to fit the optional header. Earlier i386 bypasses cannot
  exploit the short-table path because their machine remains i386 and fails the
  requested ARM64/x64 machine check.
- The parser does not attempt to reproduce every Windows loader validation rule
  (for example, all alignment and import-table semantics). Packaged launch remains
  the authoritative end-to-end proof; this review accepts the bounded structural
  claim rather than treating the parser as a complete Windows loader.

### Native ARM64 MakeAppx disposition

The native ARM64 MakeAppx host was independently located, PE-inspected, and
executed. A fresh disposable pack/unpack matrix was not completed in this bounded
review. The isolated branch's `build-development-msix.ps1` calls a pre-integration
x64-only `build-release.ps1` that lacks the required `-Architecture` parameter, so
it cannot produce the real ARM64 product layout here without forbidden source
changes. The lane evidence in `9859fb6` records clean ARM64 and AMD64 fixture
pre-pack/post-unpack passes and x86-contaminated ARM64 rejection at both gates; this
final review does not relabel that worker result as an independent rerun.

## Residual closure

| `0a1c153` residual | Final result | Independent evidence |
| --- | --- | --- |
| `BUILD-RV-MSIX-001` main-host structural proof incomplete | **Closed for integration** | Launchability fixture passed all five invalid structures; implementation verifies matching native PE32+ executable, subsystem, entry point, and executable file-backed section. |
| `BUILD-RV-MSIX-002` Application namespace not enforced | **Closed** | Exact foundation XPath and foreign local-name defense reviewed; extra, foreign, and mismatched Application/executable fixtures all rejected. |
| `BUILD-RV-MSIX-003` short data-directory table falsely rejected | **Closed** | Compact native image with zero directories accepted; prior malformed i386/CLR cases remained rejected. |

No new reproducible architecture-contamination regression was found in
`9859fb6`. The commit is **accepted for coordinator integration**, subject to the
integrated dual-RID build/package matrix and release gates below.

## Release gates

- Native ARM64 and x64 self-contained product layouts must be built by the
  integrated architecture-aware release script, validated before packing,
  unpacked, and validated again.
- The ARM64 package must be installed and launched on physical Windows 11 ARM64;
  this VM packaging evidence is not physical-device runtime proof.
- x64 Windows CI must execute its package tests and product smoke tests; neither
  x64 CI nor x64-on-ARM64 emulation is native-x64 physical hardware proof.
- Native-x64 physical installation/launch validation remains an explicit release
  gate.
