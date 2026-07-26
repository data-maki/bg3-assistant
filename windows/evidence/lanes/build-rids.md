# Build/RID lane

## Q/A before changes

**Hypothesis**

The Windows build currently relies on implicit or x64-specific defaults in shared MSBuild properties, test hosts, scripts, or CI. If so, an ARM64 request can restore, build, test, or publish a mixture of `win-arm64`, `win-x64`, and architecture-neutral outputs without failing early.

**Evidence to collect**

- Every Windows project, lock file, solution entry, PowerShell build/test/publish script, and GitHub workflow reference to `RuntimeIdentifier`, `RuntimeIdentifiers`, `Platform`, `PlatformTarget`, `x64`, `arm64`, `win-x64`, `win-arm64`, `AnyCPU`, or architecture-neutral packaging.
- Locked restore results and resolved runtime/native assets for both supported RIDs.
- Build/test/publish output paths, generated `.deps.json` runtime targets, PE machine types, and absence of the opposite architecture's native assets.
- CI jobs that execute x64 tests on an x64 Windows runner, separately from cross-build checks.

**Unknowns**

- Whether this physical host and installed .NET/Windows SDK toolchain are ARM64 or x64.
- Whether all locked package graphs already contain complete ARM64 assets.
- Whether Windows App SDK packaging targets accept a shared explicit RID input without project-specific overrides.
- Whether repository CI exists outside the checked-out worktree.

**Acceptance tests**

1. The only accepted architecture inputs are `arm64`/`win-arm64` and `x64`/`win-x64`; missing, mismatched, `x86`, `win-x86`, and arbitrary values fail with an actionable error.
2. A single explicit input selects consistent `Platform`, `PlatformTarget`, and `RuntimeIdentifier` values across app, libraries, tests, and test hosts.
3. Locked restore, build, test, and self-contained publish are independently invokable for both RIDs without cross-RID asset contamination.
4. CI restores locked dependencies, builds, tests, publishes, and retains inspectable evidence for both RIDs; x64 execution occurs on an x64 Windows runner and cross-build is not reported as execution.
5. Published PE/dependency metadata and artifact names identify the requested architecture; no `AnyCPU`, neutral native payload, or 32-bit x86 output is accepted.

## Findings and results

### Environment classification

- Host OS ISA: ARM64, Windows 11 build 26200, running as a Parallels ARM virtual machine on Apple Silicon. This is **native-ISA ARM64 VM evidence, not physical ARM64 hardware evidence**.
- PowerShell process used by the PE inspector: ARM64.
- Installed .NET SDK/host: 10.0.302/10.0.10 x64 (`win-x64`) running under Windows x64-on-ARM64 emulation. Local x64 test results below are **emulated**, not native-x64 hardware results.
- No ARM64 .NET SDK/runtime was installed, so this lane cross-built/published ARM64 but did not execute ARM64 tests. The workflow now assigns ARM64 execution to `windows-11-arm`; physical ARM64 and physical native-x64 remain release gates outside this lane.

### Defects

| ID | Architecture | Severity | Reproduction and evidence | Root cause | Fix and regression test | Reviewer result | Residual risk |
|---|---|---:|---|---|---|---|---|
| BUILD-RID-01 | arm64, x64 | Critical | Before the fix, `Directory.Build.props` returned `PlatformTarget=x64`, `Platforms=x64`, while App, GameWindowHost, and OverlayHarness each declared `RuntimeIdentifier=win-x64`. Supplying an ARM64 intent could not change the graph consistently. | Architecture was an implicit shared x64 default plus repeated executable-project overrides. | Require `-p:BG3Architecture=arm64|x64`; derive and validate RID, platform, and platform target centrally; reject missing, x86, RID mismatch, platform mismatch, and changed supported-RID lists. Direct MSBuild negative cases now fail with the expected actionable errors. | Pending independent reviewer. | Visual Studio configuration switching has not been exercised in this lane. |
| BUILD-RID-02 | arm64 | High | Lock audit showed only App and two spikes had `win-x64` targets; all other locks were architecture-neutral. A locked ARM64 restore therefore had no complete per-project ARM64 graph. | Locks reflected the x64-only/neutral project declarations rather than the two supported runtime graphs. | Declare exactly `win-x64;win-arm64` centrally and regenerate all 11 project lock files. Locked solution restores pass for both explicit inputs, and every lock now contains both RID targets. | Pending independent reviewer. | NuGet server availability and future package updates can change asset graphs; CI retains locked mode. |
| BUILD-RID-03 | arm64 | Critical | `tools/build-release.ps1` defaulted its path to `win-x64`, passed `--runtime win-x64`, and used a user-local SDK path. Invoking it for ARM64 was impossible; invoking from the repository root also bypassed `windows/global.json`. | The release contract encoded one developer machine and one RID instead of accepting architecture. | Make `-Architecture arm64|x64` mandatory, derive `win-$Architecture`, resolve `dotnet` from `PATH`, run from the Windows root so `global.json` is honored, and isolate outputs under `artifacts/publish/<RID>`. Both publishes passed PE/deps inspection. | Pending independent reviewer. | Signing/MSIX creation belongs to the packaging lane and was not exercised here. |
| BUILD-RID-04 | arm64, x64 | Critical | CI restored and built only the app on `windows-latest`; it ran no tests and did not publish, package, inspect, or retain architecture evidence. It could not detect test-host, solution, or native-asset contamination. | CI had no architecture matrix and no full-solution or artifact validation. The solution itself exposed only inferred AnyCPU configuration/mappings. | Add explicit x64 (`windows-latest`) and ARM64 (`windows-11-arm`) jobs, verify runner ISA, locked-restore/build/test all projects, self-contained publish, package, PE/deps/MSIX inspection, and artifact upload. Add exact x64/arm64 SLNX configurations/mappings and a solution-level architecture projection. | Pending CI run and independent reviewer. | The workflow depends on the packaging lane's matching `build-development-msix.ps1 -Architecture` contract. GitHub CI has not run from this branch. Neither CI VM is physical native-x64 hardware proof. |

### Regression checks performed

| Check | Result | Evidence/qualification |
|---|---|---|
| PowerShell parse of `inspect-architecture.ps1` | Pass | No parser errors. |
| Missing `BG3Architecture` | Expected failure | `BG3Architecture is required. Pass -p:BG3Architecture=x64 or ...=arm64.` |
| `BG3Architecture=x86` | Expected failure | Explicit unsupported-value/32-bit rejection. |
| `BG3Architecture=arm64` plus `RuntimeIdentifier=win-x64` | Expected failure | Explicit conflict reports expected `win-arm64`. |
| Locked restore, x64 and arm64 | Pass | `dotnet restore BG3HonorAssistant.slnx --locked-mode -p:BG3Architecture=<arch>`; 11 projects, both inputs. |
| ARM64 app build | Pass | Zero warnings/errors; outputs under `bin/arm64/.../win-arm64`. This was a cross-build by the emulated x64 SDK. |
| x64 app build | Pass | Zero warnings/errors; outputs under `bin/x64/.../win-x64`. This was an emulated x64 SDK build on the ARM64 VM. |
| Self-contained ARM64 publish inspection | Pass | App host and enumerated native runtime/SQLite/WPF files are PE `0xAA64`; deps runtime target ends in `win-arm64`. Inspector itself ran ARM64. |
| Self-contained x64 publish inspection | Pass | App host and enumerated native runtime/SQLite/WPF files are PE `0x8664`; deps runtime target ends in `win-x64`. |
| Cross-contamination negative check | Expected failure | Inspecting the x64 publish as ARM64 rejects `BG3HonorAssistant.exe` (`expected 0xAA64, found 0x8664`). |
| Full ARM64 solution build | Blocked outside lane | Architecture mapping worked and emitted ARM64/RID-isolated outputs. Existing xUnit2031 warnings-as-errors at `RoutePlannerRulesTests.cs:53,75` stopped the build (coordinator ID BG3-WIN-006). |
| x64 App tests under emulation | 8 pass, 8 fail | Failures are fixed-depth guide-path discovery exposed by `bin/x64/...` (BG3-WIN-007). See `results/BG3HonorAssistant.App.Tests-x64-emulated.trx`. |
| x64 Infrastructure tests under emulation | 74 pass, 2 fail | Same BG3-WIN-007 path class. See `results/BG3HonorAssistant.Infrastructure.Tests-x64-emulated.trx`. |
| x64 Package tests under emulation | 0 pass, 9 fail | Same BG3-WIN-007 repository-root path class. See `results/BG3HonorAssistant.Package.Tests-x64-emulated.trx`. |
| x64 Windows tests under emulation | 35 pass, 2 fail | Same BG3-WIN-007 host-output path class; controlled host was built under `bin/x64/...`. See `results/BG3HonorAssistant.Windows.Tests-x64-emulated.trx`. |
| x64 Core tests under emulation, warnings-as-errors disabled only to expose runtime results | 159 pass, 1 fail | One BG3-WIN-007 artwork-path failure; normal full build remains correctly blocked by BG3-WIN-006. See `results/BG3HonorAssistant.Core.Tests-x64-emulated-warning-override.trx`. |

### Acceptance disposition

1. Exact architecture-input validation: **pass locally**.
2. Consistent RID/platform/platform-target projection: **pass locally** for direct projects and SLNX mappings.
3. Locked restore/build/self-contained publish with contamination inspection: **restore and app publish pass for both**; full solution green is pending BG3-WIN-006/007 integration.
4. Matching-architecture CI: **implemented, not yet run**. Do not interpret local x64 emulation or cross-built ARM64 as CI execution.
5. Architecture-specific PE/dependency/artifact labeling: **publish inspection pass**; separate MSIX validation depends on the packaging lane and remains pending.
