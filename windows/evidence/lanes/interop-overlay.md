# Interop and overlay lane

## Q/A before changes

### Hypotheses

1. The product P/Invoke surface is architecture-safe because handles, callbacks, and
   pointer-sized Win32 values use `nint`, while Win32 `DWORD`, coordinates, process
   IDs, and `RECT` fields use fixed-width 32-bit values.
2. The controlled BG3 host is not architecture-safe as test infrastructure: its
   project, lookup path, PE assertion, and lock file are hard-coded to `win-x64`.
   On this ARM64 device that means the existing integration proof exercises x64
   emulation, not native ARM64.
3. Name matching is broader than "exact executable name" because
   `Path.GetFileNameWithoutExtension` accepts a full path ending in `bg3.exe`.
4. Overlay placement should remain in physical coordinates and preserve foreground
   focus across windowed/borderless moves, negative virtual-screen coordinates,
   minimize/restore, and close/relaunch. The current deterministic host covers most
   of that lifecycle but does not cover relaunch and hard-codes x64.
5. Failed `GetWindowLongPtrW`/`SetWindowLongPtrW` calls are not distinguished from a
   legitimate zero return, so invalid HWNDs may proceed with misleading state.

### Evidence

- `GameWindowHost.csproj` and `OverlayHarness.csproj` set
  `<RuntimeIdentifier>win-x64</RuntimeIdentifier>`.
- `ControlledGameWindowIntegrationTests` looks only under `win-x64`, asserts PE
  machine `0x8664`, and names its test `ExactNameX64Host...`.
- Both spike lock files contain only a `win-x64` target.
- `Bg3ProcessNames.IsSupported` normalizes with
  `Path.GetFileNameWithoutExtension`, which accepts paths rather than exact names.
- HWNDs, WinEvent hook handles, process handles, callback context, callback window
  handles, `WPARAM`, and `LPARAM` are represented as `nint`; process IDs and Win32
  `DWORD` flags remain `uint`; `RECT` fields remain `int`.
- Baseline environment observation on 2026-07-26:
  Windows 11 Pro `10.0.26200`, OS architecture ARM64, ARM64 PowerShell process,
  8-byte pointers. `Win32_ComputerSystem` identifies `Parallels ARM Virtual
  Machine`, manufacturer `Parallels International GmbH.`, and
  `HypervisorPresent=True` on an Apple Silicon host. This is an ARM64 VM and is
  never physical Windows ARM64 hardware evidence.
- The installed .NET 10.0.302 SDK/host is x64 (`dotnet --info` RID `win-x64`) and
  therefore runs emulated on this ARM64 OS. A self-contained `win-arm64` controlled
  host was proven as PE `0xAA64` and native-ISA ARM64 by the OS, but the xUnit
  process driving it remained x64-emulated. This is not native ARM64 packaged
  product-process proof.

### Unknowns

- Whether an ARM64 self-contained controlled host can be cross-published by the
  installed x64 SDK and launched natively on this device.
- Whether all solution-level architecture inputs expected by the coordinator's
  build lane are available yet; this lane will keep host RID selection explicit and
  isolated.
- Available monitor count/DPI topology in the ARM64 VM during the run.
- Native BG3 availability and its process architecture are outside this controlled
  host lane and must be recorded separately if exercised.

### Acceptance tests

1. Restore/build/publish the controlled host for exactly `win-arm64` and `win-x64`
   from explicit RID inputs; inspect PE machine (`0xAA64`/`0x8664`) and reject any
   mismatched host before launch.
2. On Windows 11 ARM64, with the environment honestly labeled as VM or physical
   hardware, run exact-name `bg3.exe` and `bg3_dx11.exe` native-ISA ARM64 hosts and
   verify detection, physical-coordinate bounds/DPI, borderless/windowed geometry,
   negative coordinates where available, overlay follow/resize, minimize/restore,
   close/relaunch, and foreground preservation.
3. Run the x64 host on ARM64 only as an explicitly labeled emulated smoke test.
4. Unit-test exact process-name rejection for paths, near misses, and unsupported
   suffixes.
5. Unit/integration-test pointer-sized style/handle behavior and invalid-HWND error
   propagation.
6. Record OS/process/PE architecture, display topology, commands, and outcomes
   without describing x64-on-ARM64 as native-x64 hardware evidence.

## Findings

### WIN-INT-001: controlled-host test path and assertion fixed to x64

- Architecture: both; observed most directly on ARM64.
- Severity: high (false architecture evidence / ARM64 test cannot start).
- Reproduction: build or publish `GameWindowHost` for `win-arm64`, set up the
  controlled lifecycle test, and observe that it searches only `win-x64` and
  asserts PE machine `0x8664`.
- Root cause: `FindHostOutput`, the PE assertion, a constant, and the test name
  encoded x64 rather than consuming a target RID.
- Fix in this lane: matrix jobs select `BG3_CONTROLLED_HOST_RID` explicitly as
  `win-arm64` or `win-x64`; local runs derive only those same RIDs from the actual
  executing test-process architecture. The test selects that RID output
  (preferring self-contained `publish`), maps it to PE `0xAA64`/`0x8664`, rejects
  mismatches before launch, and records the live OS process observation. Spike
  project/lock configuration was deliberately left to the build/RID lane.
- Regression test: both exact-name theory rows run against each explicit RID.
- Reviewer result: invalidated by independent review `e88f445` because the first
  lookup omitted the integrated `bin/<architecture>/...` segment; corrected in
  the follow-up described below.
- Residual risk: build-lane integration must produce both RID directories and set
  the environment input in CI/VM jobs.

### WIN-INT-002: executable matching accepted paths, not exact names

- Architecture: both.
- Severity: medium.
- Reproduction: `Bg3ProcessNames.IsSupported(@"C:\Games\...\bg3.exe")` returned
  true although the input was not the exact process/executable name.
- Root cause: `Path.GetFileNameWithoutExtension` silently normalized arbitrary
  paths before matching.
- Fix: compare case-insensitively against exactly `bg3`, `bg3.exe`, `bg3_dx11`,
  and `bg3_dx11.exe`.
- Regression test: exact documented forms pass; full paths, whitespace, double
  extensions, launcher, Steam, mod-like names, and empty input fail.
- Reviewer result: invalidated by independent review `REV-INT-001`; the direct
  matcher was strict but the production locator stripped an arbitrary final
  extension before calling it. Corrected at the trusted image-name boundary below.
- Residual risk: none known; the locator already extracts a basename from the
  trusted full process image path before calling this matcher.

### WIN-INT-003: pointer-sized window-style failures were ignored

- Architecture: both 64-bit targets.
- Severity: medium.
- Reproduction: call `OverlayWindowService.Configure` with nonzero invalid HWND
  `0x1234`; the prior implementation continued after a zero
  `GetWindowLongPtrW`/`SetWindowLongPtrW` return.
- Root cause: zero is both a valid previous style value and the API failure
  sentinel; the code did not inspect the last P/Invoke error.
- Fix: preserve `nint` throughout and throw `Win32Exception` only when the return
  is zero and `Marshal.GetLastPInvokeError()` is nonzero.
- Regression test: invalid pointer-sized HWND deterministically reports Win32
  error 1400 while a valid zero-style window still configures successfully.
- Reviewer result: resisted independent invalidation; pointer-sized declarations
  and the valid-zero/error distinction were confirmed.
- Residual risk: no 32-bit x86 path is supported or tested, by design.

### WIN-INT-004: `IsWow64Process2` alone mislabeled x64 emulation on ARM64

- Architecture: x64 on ARM64.
- Severity: medium (evidence integrity).
- Reproduction: launch the verified x64 PE on this Windows ARM64 VM.
  `IsWow64Process2` reported process machine `UNKNOWN` and native machine ARM64,
  which a naive formatter called native ARM64.
- Root cause: the API's process-machine value does not by itself identify the x64
  emulator behavior on this OS build.
- Fix: classify with both the independently read PE machine and the OS native
  machine. PE x64 on native ARM64 is labeled `emulated-x64-on-arm64`; PE ARM64 on
  native ARM64 is `native-isa-arm64`.
- Regression test: the controlled host rejects PE/RID contamination before launch
  and validates the combined live observation for both RIDs.
- Reviewer result: resisted independent invalidation; PE plus native-machine
  classification and unsupported-RID rejection were confirmed.
- Residual risk: native-x64 physical hardware remains untested and must not be
  inferred from x64 CI or this emulation result.

### WIN-INT-005: emulated WPF startup exceeded the prior deterministic bound

- Architecture: x64 on ARM64 emulation.
- Severity: low.
- Reproduction: the first self-contained x64 controlled WPF host did not expose a
  visible main window within the old 10-second bound; a subsequent case started
  but the run failed earlier on the architecture-label assertion.
- Root cause: x64-on-ARM64 cold startup in this VM can exceed 10 seconds.
- Fix: increase the controlled-operation bound to 30 seconds; polling remains at
  50 ms and no product retry/sleep behavior was added.
- Regression test: final x64-emulated windowed and borderless lifecycle cases pass.
- Reviewer result: no further defect reported by independent review; bounded
  emulated startup remained explicit.
- Residual risk: CI load can still cause bounded infrastructure timeouts; failures
  remain explicit rather than silently passing.

### WIN-INT-006: controlled test assumed foreground activation permission

- Architecture: both; reproduced during x64-on-ARM64 emulation.
- Severity: low (test determinism).
- Reproduction: after removing `WS_EX_NOACTIVATE`, call
  `SetForegroundWindow` on the controlled overlay. Windows can return false under
  foreground-lock policy because the call is not backed by real user input.
- Root cause: the test treated OS-granted foreground permission as deterministic,
  although product activation occurs in a user click handler.
- Fix: continue to verify the interactive style transition, but do not require the
  harness to steal foreground. Restore passive mode, make the controlled game
  foreground, and retain the stronger assertion that subsequent overlay
  positioning never changes it.
- Regression test: both controlled modes cover interactive/passive style bits and
  no-focus overlay placement.
- Reviewer result: no further defect reported by independent review; the reviewer
  confirmed the later strict foreground-preservation assertion remained useful.
- Residual risk: packaged UI click activation remains part of product-flow QA,
  outside this deterministic native window harness.

## Independent review corrections

Independent review commit `e88f44586b3f55b1489e85fab008bd3768c19235`
invalidated worker commit `0f23459` with three reproducible integration defects.
The follow-up dispositions are:

### REV-INT-001: production locator accepted alternate/double extensions

- Architecture: both; reviewer reproduced under x64-on-ARM64 emulation.
- Severity: high.
- Reproduction: run a visible controlled host as `bg3.exe.exe`; the old locator
  stripped the final `.exe`, passed `bg3.exe` to the strict matcher, and returned
  the lookalike HWND. `bg3.scr` similarly normalized to the accepted bare name.
- Root cause: exact matching occurred after `Path.GetFileNameWithoutExtension`,
  outside the trusted full-image-name boundary.
- Fix: `QueryFullProcessImageNameW` output is reduced only to its full file name,
  which must case-insensitively equal exactly `bg3.exe` or `bg3_dx11.exe`. Only
  after that succeeds is the known `.exe` suffix removed for presentation.
- Regression tests: strict filename unit cases plus real visible controlled hosts
  named `bg3.exe.exe`, `bg3.scr`, and `bg3_dx11.com`; all three production-locator
  false positives are rejected.
- Reviewer result: original commit invalidated; correction implemented and worker
  regression matrix passed. Coordinator re-review remains the acceptance step.
- Residual risk: access-denied and process-exit races remain intentionally treated
  as non-candidates.

### REV-INT-002: cross-thread disposal silently leaked WinEvent hooks

- Architecture: both; reviewer reproduced under x64-on-ARM64 emulation.
- Severity: high.
- Reproduction: call `Start` on one OS thread and `Dispose` on another. Windows
  rejects cross-thread `UnhookWinEvent`, while the old monitor ignored both
  failures and discarded both handles.
- Root cause: hook ownership thread was not recorded; disposal treated unhook as
  best-effort.
- Fix: record the installing OS thread with `GetCurrentThreadId`; reject
  cross-thread disposal without changing state; dispose on the owner thread;
  verify both unhook calls; retain any handle whose unhook fails; surface
  aggregated cleanup errors; and prevent restart while cleanup is incomplete.
- Regression test: real `Start` installs hooks on a dedicated thread, cross-thread
  `Dispose` throws, and disposal on the original installing thread succeeds.
- Reviewer result: original commit invalidated; correction implemented and the
  real-hook regression passed. Coordinator re-review remains the acceptance step.
- Residual risk: product lifecycle must continue disposing the monitor on its WPF
  UI/start thread; violations now fail visibly instead of leaking silently.

### REV-INT-003: host lookup missed integrated architecture-first output

- Architecture: arm64 and x64.
- Severity: high (matrix blocker).
- Reproduction: integrated build output exists under
  `bin/<architecture>/<configuration>/<TFM>/<RID>`, while the first worker lookup
  searched only `bin/<configuration>/<TFM>/<RID>`.
- Root cause: the test helper did not share the build lane's explicit platform
  directory contract.
- Fix: search architecture-first output before the temporary legacy layout,
  including optional `publish` directories. Inspect every existing candidate and
  reject any PE machine conflict instead of silently selecting a clean-looking
  neighbor.
- Regression tests: a synthetic `bin/arm64/Debug/.../win-arm64` layout resolves;
  an ARM64 integrated candidate plus a stale x64 legacy candidate is rejected.
- Reviewer result: original commit invalidated; correction implemented and both
  layout tests passed. Coordinator re-review remains the acceptance step.
- Residual risk: the build lane remains responsible for actually emitting both
  explicit platform/RID outputs.

## Results and reflection

### Commands and results

- Locked restore of the focused Windows test project: passed before the
  architecture-specific experiments.
- Focused Windows build: the initial clean build passed with 0 warnings and
  0 errors. The final incremental compile passed with 0 errors and four MSB4011
  warnings caused by duplicate ignored `obj/*.nuget.g 2.props` files created by
  the Parallels shared-filesystem experiment; no warning originates from a source
  or committed file.
- Focused unit/WPF run:
  `Bg3ProcessNamesTests`, `Bg3WindowMonitorTests`, `OverlayPlacementTests`, and
  `OverlayWindowServiceTests`: 29 passed, 0 failed.
- Post-review focused run expanded to 42 passed, 0 failed, covering strict image
  filenames, real hook ownership/cleanup, architecture-first host lookup, and
  conflicting-PE rejection.
- Post-review end-to-end false-positive run under x64-on-ARM64 emulation:
  `bg3.exe.exe`, `bg3.scr`, and `bg3_dx11.com`: 3 passed, 0 failed.
- Explicit `win-arm64` self-contained controlled host:
  PE `0xAA64`; Windows live observation `native-isa-arm64`; exact-name
  `bg3.exe` borderless and `bg3_dx11.exe` windowed cases: 2 passed, 0 failed.
  The driver/test process was x64-emulated, the VM had one monitor, and DPI was
  192. Both cases covered detection, resize/move to negative virtual coordinates,
  overlay placement without foreground change, interactive/passive style
  transition, minimize/restore, close, exact-name relaunch, and final close.
  Final source-state rerun: 2 passed, 0 failed in 1 minute 4 seconds.
- Post-review native-ISA ARM64 VM exact-name rerun: 2 passed, 0 failed in
  23 seconds. The xUnit driver remained x64-emulated.
- Explicit `win-x64` self-contained controlled host on ARM64:
  PE `0x8664`; labeled `emulated-x64-on-arm64`; the same two cases passed 2/2
  after the evidence-classification and timeout corrections. Final explicit/local
  source-state runs passed 2/2; the final local architecture-derived run completed
  in 1 minute 57 seconds.
- Post-review x64-on-ARM64 emulated exact-name rerun: 2 passed, 0 failed in
  53 seconds.
- Multi-monitor count was 1, so no real multi-monitor transition was available.
- BG3 itself was not used; no BG3 process architecture claim is made.
- All temporary project/lock changes needed to make pre-integration experiments
  against the old x64-only build props were restored exactly. This lane's commit
  contains no spike project/lock or shared build-file changes.

### Reflection and release gates

- The owned P/Invoke audit found no fixed 64-bit handle assumptions: HWND, process
  handles, callback context, hooks, `WPARAM`, and `LPARAM` remain `nint`; Win32
  `DWORD`, process IDs, coordinates, and `RECT` fields remain 32-bit by API
  contract. The lane adds no helper executable and requires no x64-only helper on
  ARM64.
- The controlled-host matrix provides useful native-ISA ARM64 VM and x64-emulated
  lifecycle evidence, but it does not satisfy physical ARM64 packaged-product QA.
- Still required outside this lane: native ARM64 packaged product-process tests,
  install/restart/upgrade/uninstall and full product flows on physical Windows 11
  ARM64; x64 Windows CI execution; and physical native-x64 hardware validation as
  an explicit release gate.
