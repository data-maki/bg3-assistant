# BG3 Honor Assistant Windows Lab Report

## Scope and evidence rules

Goal: harden one source tree for exactly `arm64`/`win-arm64` and
`x64`/`win-x64`, producing separate self-contained, architecture-specific MSIX
packages.

Evidence is classified as:

- **Native ARM64 VM:** executed by an ARM64 process in Windows 11 ARM64 under
  Parallels on Apple Silicon. This is native-ISA execution, but not physical
  Windows ARM64 hardware proof.
- **Physical ARM64:** required release evidence from a physical Windows 11
  ARM64 device; unavailable in the current environment.
- **x64 CI:** executed on a GitHub-hosted x64 Windows runner; this is not proof
  from native-x64 hardware controlled by this project.
- **Emulated x64:** executed by an x64 process under Windows 11 ARM64 emulation.
- **Native x64 physical:** unavailable and remains an explicit release gate.
- **Cross-build only:** compilation or packaging without executing the target.

No cross-build, CI run, or emulated run may be presented as native-x64 physical
proof.

The 2026-07-27 completion milestone below supersedes the earlier dual-RID
scope. That milestone targets only `arm64`/`win-arm64`; it did not build,
review, package, or test the x64/AMD64 distribution.

## 2026-07-26 — Initial audit

### Q/A before experiments

**Hypothesis**

The Windows source and release path assume x64 globally, so an apparent ARM64
build either fails, is mislabeled, or contains x64 payloads. Existing local
test evidence is likely x64-emulated because the installed .NET host may not be
native ARM64.

**Evidence already observed**

- Guest OS reports Windows 11 Pro, ARM64, build 26200.
- Hardware audit reports `Parallels ARM Virtual Machine` with
  `HypervisorPresent=True`; this environment cannot satisfy physical ARM64
  hardware proof.
- The PowerShell process reports ARM64.
- `dotnet --info` reports RID `win-x64`, host architecture `x64`, and only an
  x64 SDK/runtime installation.
- `windows/Directory.Build.props` sets both `PlatformTarget` and `Platforms` to
  `x64`.
- `windows/src/BG3HonorAssistant.App/BG3HonorAssistant.App.csproj` sets
  `RuntimeIdentifier` to `win-x64`.

**Unknowns**

- Whether all project/test hosts accept explicit architecture inputs.
- Whether the MSIX manifest, packaging scripts, SDK tools, and produced PE
  files agree on architecture.
- Whether NuGet/native assets resolve cleanly for both RIDs.
- Whether P/Invoke declarations and pointer-sized values are architecture-safe.
- Whether ARM64-native controlled BG3-name hosts can exercise overlay behavior.
- Whether persistence, credentials, startup, tray, product flows, and direct
  OpenRouter behavior remain correct when packaged.
- Whether current CI restores locked dependencies and executes x64 tests on an
  x64 Windows runner.

**Acceptance tests**

- Reject missing, `x86`, `AnyCPU`, neutral, or unsupported architecture inputs.
- Locked restore, build, tests, self-contained publish, package, and artifact
  inspection pass for `win-arm64` and `win-x64`.
- PE headers, manifest architecture, filenames, and package metadata agree.
- ARM64 tests execute through an ARM64 `dotnet` host in the current VM.
- The same matrix is repeated on physical Windows 11 ARM64 before release.
- x64 tests execute in x64 Windows CI and separately smoke-test under ARM64
  emulation.
- Native ARM64 controlled hosts named exactly `bg3.exe` and `bg3_dx11.exe`
  validate detection and overlay lifecycle/geometry/DPI behavior.
- Packaged ARM64 install/restart/upgrade/uninstall and product-flow checks pass.
- Native-x64 physical validation is documented as an unmet release gate.

### Results and reflection

The live macOS source audit established these parity contracts without changing
`mac/`:

- startup uses the platform-native login-item API;
- OpenRouter credentials use the platform-native credential vault;
- run, preferences, and overlay anchor state survive restart;
- game detection and overlay geometry are driven from live application/window
  state;
- the macOS tree still has local model and bundled-backend paths, but the
  requested Windows product boundary intentionally excludes both.

The pre-hardening Windows run used the installed x64 .NET host under ARM64
emulation. Locked restore succeeded, and the solution produced `win-x64`
outputs. It then exposed reproducible failures:

- package policy tests read pre-refactor paths (`MainWindow.xaml` and
  `TrayMenu.cs`) and failed 3 of 9 tests;
- two core test assertions violate xUnit analyzer rule xUnit2031, which is an
  error because warnings are treated as errors;
- shared-guide discovery failed in infrastructure and application tests after
  the source/layout refactor (2 infrastructure failures and 8 application
  failures);
- the passive WPF overlay test timed out;
- two controlled exact-name x64 host cases failed their readiness assertion.

Passing counts observed before the overall failure included 6 package, 74
infrastructure, 34 Windows, and 8 application tests. Core did not compile
because of the analyzer errors. Results are stored under
`windows/evidence/prehardening-emulated-x64/`.

Reflection: the original CI's build-only Windows job would not reveal these
failures. Runtime architecture must be emitted by the test harness because
physical OS architecture alone is insufficient on Windows ARM64.

## 2026-07-26 — Native ARM64 test host

### Hypothesis before experiment

An isolated ARM64 .NET SDK of the same pinned version will allow genuinely
native ARM64 restore/build/test execution without changing the machine's
existing x64-emulated SDK.

### Result

The official .NET install script installed SDK `10.0.302` at
`C:\Users\jcarbs\AppData\Local\Microsoft\dotnet-arm64`. Its own
`dotnet --info` reports:

- RID: `win-arm64`
- host architecture: `arm64`
- SDK: `10.0.302`
- Windows Desktop runtime: `10.0.10`

This establishes a native-ISA ARM64 test host inside the Parallels VM. It does
not establish physical ARM64 device coverage and does not itself prove that any
app output is ARM64; subsequent tests must also inspect the produced PE/MSIX
and launched process.

## 2026-07-26 — MSIX invalidation review

### Hypothesis before experiment

The first packaging fix may mistake an x86 or mixed-mode CLR PE for
architecture-neutral IL because it checks only for a nonzero CLR data-directory
RVA.

### Result

The reviewer reproduced the bypass. An ARM64 package layout containing a
matching ARM64 app host plus the real .NET Framework x86
`CustomMarshalers.dll` passed pre-pack validation, ARM64-native MakeAppx pack
and unpack, and post-unpack validation. Reflection identifies the added
assembly as x86. A synthetic i386 PE with a forged CLR RVA also passed.

The layout validator additionally accepted a manifest with two application
entries. The packaging commit is rejected pending a worker fix that validates
CLR header bounds/flags and enforces a single matching application entry.

### Worker follow-up

Packaging follow-up commit `369b2d0` now requires a structurally valid
architecture-neutral CLR image (bounded CLI/metadata, IL-only flags, no
32-bit-required/preferred/native entry point, and no managed-native/R2R header),
and exactly one application entry for `BG3HonorAssistant.exe`. Package tests
pass 14/14; the real x86 assembly and all reviewer bypass fixtures reject.
Clean ARM64 and AMD64 synthetic packages pass native ARM64 MakeAppx pre/post
inspection. Independent re-review is still required before integration.

## 2026-07-26 — Build/RID invalidation review

The first build/RID commit is rejected pending follow-up:

- adding an ARM64 PE under an unlisted filename to an x64 publish still produces
  a passing architecture report because the inspector checks a fixed filename
  list rather than every PE;
- callers can override derived validation properties in matching pairs and
  bypass the intended architecture invariant;
- selecting a solution ARM64 platform without the separate property fails all
  projects, so solution/IDE mapping is one-way;
- ARM CI checks OS architecture but not the .NET/testhost process ISA;
- a project with `IsTestProject=false` can exit zero with no tests, and CI checks
  only exit status;
- CI's `10.0.x` SDK request is not pinned to `windows/global.json` `10.0.302`.

Locked restores, publish PE/deps labels, and SQLite assets for both RIDs did pass
the reviewer’s positive checks.

## 2026-07-26 — Interop invalidation review

The first interop commit is rejected pending follow-up:

- production path normalization strips only the final extension, so
  `bg3.exe.exe` reaches the exact-name matcher as `bg3.exe` and is accepted;
- disposing the window monitor from a different OS thread silently fails to
  unhook both WinEvent hooks and clears the stored handles, proving a leak;
- integrated build output is under `bin/<arch>/<configuration>/.../<rid>`, but
  controlled-host discovery still searches the pre-integration path.

The remaining focused x64-emulated tests passed 29/29, and unsupported `win-x86`
input rejected as expected.

## 2026-07-26 - Wave 1 acceptance and package matrix

### Results and reflection

Independent re-reviews accepted the corrected build/RID, packaging, and interop lanes. Recursive PE inspection, non-overridable architecture/RID derivation, symmetric solution platforms, exact SDK/test-host checks, zero-test rejection, structural CLR validation, single-app manifest validation, native-tool launchability, exact process-name matching, owner-thread WinEvent disposal, pointer-sized native handles, and architecture-aware controlled-host discovery all passed their focused adversarial suites.

Exact-name host execution passed 2/2 through a native-ISA ARM64 host in the Parallels VM and separately 2/2 through x64-on-ARM64 emulation. These are VM/runtime results, not physical ARM64 or physical native-x64 hardware proof.

Using the isolated ARM64 SDK 10.0.302, locked restore passed all 11 projects. The ARM64 packaging path published a self-contained win-arm64 layout, recursively validated it, packed with native ARM64 MakeAppx, unpacked it, and validated it again. Artifact: windows/artifacts/BG3HonorAssistant_0.1.0.0_arm64_unsigned.msix. Classification: native-ISA ARM64 execution inside a Parallels ARM VM; physical ARM64 install/lifecycle validation remains unmet.

## 2026-07-26 - x64 package experiment

### Q/A before experiment

Hypothesis: the same source will emit a separate self-contained win-x64 package under x64-on-ARM64 emulation with AMD64 manifest, PE, CLR, native NuGet asset, and filename labels and no ARM64 or x86 contamination.

Evidence: the guest OS and PowerShell are ARM64; the x64 SDK 10.0.302 reports host architecture x64 and RID win-x64. An earlier x64 artifact predates final Wave 1 integration and is not accepted as current evidence.

Unknowns: whether locked restore and packaging still pass at the integrated commit, whether every post-unpack PE is AMD64 or valid architecture-neutral IL, and whether x64 Windows CI independently executes the tests.

Acceptance tests: restore with BG3Architecture=x64 and win-x64; self-contained publish; recursive pre-pack and post-unpack inspection; reject x86, ARM64 contamination, neutral native payloads, manifest/filename mismatches, and zero-test results. Record this local result only as emulated x64 and require separate x64 Windows CI.

## 2026-07-27 - ARM64 application completion milestone

### Scope

This milestone targeted only `arm64`/`win-arm64`. No x64/AMD64 distribution
was built, reviewed, packaged, or tested. All results below are classified as
native-ISA ARM64 in a Parallels VM, not physical Windows ARM64 hardware proof.
The `mac/` tree remained read-only.

The first draft-PR workflow run (`30259250896`) was cancelled after checkout
while the historical x64 job was still in `setup-dotnet`; all x64 restore,
build, test, publish, package, inspection, and upload steps were skipped. The
CI matrix was then scoped to its ARM64 entry for this milestone.

### Integrated product result

The Windows WPF application now connects the fresh/mid-run onboarding model,
compact/expanded overlay, tray lifecycle, Now/Route, multiple runs, party,
reviewed/manual builds, loadout/gear, Act ledger, Settings, diagnostics,
startup, spoiler policy, density, and tour replay to the existing controller
and guide data.

Adversarial cross-review found and fixed:

- filtered Route completion selecting the wrong state;
- stale/incomplete party undo;
- ineffective reviewed Act gear revision;
- a run-switch/save race and silent durable queue failure;
- incoherent/rejected SQLite snapshots losing recovery evidence;
- unsafe QA data-root overrides;
- stale OpenRouter completions after cancel/key replacement;
- an executable provenance bypass using a renamed ARM64 runtime.

The coordinator's signed-package invalidation pass then found and fixed a
sprite alpha regression, recursive roster formatting crash, blank initial tab,
empty Reference overlay, illegal manual-build point buy, undecodable build/item
WebPs, retained party selection, and wrong-step Route revisit. The original
WebP assets remain authoritative; WPF receives derived lossless PNGs from the
shared resource tree.

### Persistence and lifecycle

SQLite schema v3 retains rejected recovery evidence, validates row/payload
identity and guide compatibility, serializes run transitions with queued saves,
and exposes bounded flush/seal behavior to explicit quit and session ending.
Undo, dialogs, snoozes, and chat remain transient.

Signed package upgrades through 0.2.0.11 preserved the manually exercised runs,
rename, catch-up, party/build/gear state, and settings. Immediately before the
final uninstall check, the LocalState database was 487,424 bytes with SHA-256
`0B1F5EDA635785180299C19F629B41B24605E1BBA7FCF1E4D2B19C94A09B0178`.
A cold hidden-to-tray launch, same-PID second activation, overlay collapse,
tray Open Planner/Quit, and startup off -> on -> off passed. Uninstall removed
the package family and database while retaining the external Credential Manager
entry. Reinstall of the exact signed artifact reproduced clean first launch and
left the package installed as `Arm64`/`Ok`.

### OpenRouter and product boundary

One direct client posts only to `https://openrouter.ai:443` using
`google/gemini-3.6-flash`. Settings never exposed the secret. The key was not
read during manual verification and was never printed, logged, placed in
SQLite, or packaged. Deterministic tests cover normal operation plus
authentication, rate limit, timeout, cancellation, provider, malformed,
offline, response-limit, and stale-completion cases. The live canary remains
bounded, credential-read-only, opt-in, and disabled by default.

The delivered-file validator now combines recursive PE/CLR inspection with a
dependency-derived allowlist, exact executable/package/resource anchors,
resource MZ rejection, and reparse-point rejection. No local server, listener,
gateway, Ollama/runtime, Python/Node player runtime, injection, save editing,
process-memory access, service, driver, or administrator runtime requirement
was introduced.

### Automated verification

The ARM64 .NET host executed:

- Core: 167/167
- Package: 20/20
- Infrastructure: 88/88
- Windows: 67/67
- App: 37/37
- Total: 379/379, zero failures or skips

The Windows suite's synthetic foreground cases require actual foreground input
when launched from the headless executor. Two retained diagnostic runs passed
65/67 and timed out only at the strict foreground assertion. With physical
desktop input directed to the unchanged controlled hosts, the suite passed
67/67 in three seconds. GitHub's hosted ARM64 desktop rejected foreground
acquisition even
with injected input; its workflow therefore sets `BG3_HEADLESS_CI=1` to skip
only that interactive reacquisition while retaining all other controlled-host
assertions. The strict path remains enabled and green in Parallels.

The final self-contained publish and signed MSIX passed recursive inspection:
487 publish PEs (167 ARM64 native and 320 architecture-neutral managed), 486
package PEs, and no foreign native payload. The installed executable reported
PE machine `0xAA64`; `IsWow64Process2` reported process machine `0x0000` and
native machine `0xAA64`.

### Remaining risk

The signed integration sequence now has real packaged captures for all 57
non-provider oracle rows (row 15 is absent). Rows 49/50 require an in-flight
and successful provider request; they have deterministic client/decode coverage
and WPF source/action review, but no runtime screenshot because no live canary
was authorized. Captures span the final signed integration sequence and do not
embed per-image package version metadata. The pull request therefore remains
draft.

The exact signed 0.2.0.11 artifact passed native ARM64 MakeAppx unpack and
recursive validation: 1,253 files, 486 PEs, 695 build PNGs, 51 item PNGs, zero
WebPs, and no foreign native payload. Its signed SHA-256 is
`73D8C205E1ED216C6B369272F17C98B2E4138B812E04A7BDA5F37F5DCBBDCD9B`.
All QA certificate, trust, CER, dump-registry, and temporary unpack/publish
residue was removed; the user-owned credential was not touched.

Detailed evidence, hashes, TRX results, screenshots, reviewer outcomes, and
defect records are in `windows/evidence/arm64-completion/`.
