# Interop/overlay independent review

## Q/A before review

**Hypothesis**

Commit `0f23459f660d85113af8c3a4d901cff156a77067` may pass its happy-path controlled host while still accepting false-positive process names, assuming x64 PE/process identity, truncating pointer-sized Win32 values, mishandling last-error or process races, stealing focus, leaking event hooks, or depending on x64-only tooling on ARM64. Architecture-specific output paths and DPI/monitor edge cases are particularly likely invalidation surfaces.

**Evidence to collect**

- Diff and call-path audit from exact process-name filtering through HWND discovery, event-hook lifecycle, overlay styles/placement, DPI and monitor selection.
- All P/Invoke declarations, pointer-sized parameters/results, `SetLastError` use, error handling, access-denied/exit races, and disposal behavior.
- Controlled-host build/discovery behavior under `bin/arm64/.../win-arm64` and `bin/x64/.../win-x64`.
- Native-ISA ARM64 VM versus x64-emulated process, host PE, and test evidence, explicitly distinguished from physical ARM64 and native-x64 hardware.
- Deliberate rejection cases for wrong names, suffixes, paths, wrong PE architecture, missing/exited/inaccessible processes, missing host output, and bounded timeout behavior.
- Focus/topmost/tool-window/no-activation state and movement, resize, negative coordinates, minimize/restore, close/relaunch, Windowed/Borderless-style geometry, DPI, monitor count, and event-hook cleanup evidence.

**Unknowns**

- Whether a native ARM64 .NET SDK/runtime is installed in this review worktree’s environment.
- Whether the Parallels VM exposes more than one Windows monitor or more than one physical DPI configuration.
- Whether Windows permits a deterministic access-denied process target without elevation or external helpers.
- Whether the controlled host can validate real BG3 behavior beyond exact-name/window geometry simulation.
- Whether CI or physical-device evidence exists outside this commit.

**Acceptance tests**

1. Exact-name matching accepts only `bg3.exe` and `bg3_dx11.exe`, case-insensitively where Windows semantics require it, and rejects suffix/path/lookalike false positives.
2. Each controlled host’s PE and executing process architecture matches the explicit build architecture; x64-on-ARM64 is labeled emulated and no local result is presented as native-x64 hardware proof.
3. Win32 declarations preserve pointer-sized values, capture last error correctly, tolerate exit/access races, dispose hooks idempotently, and use bounded waits.
4. Overlay windows remain passive/no-activate/tool-window/topmost as intended, never call focus-stealing APIs, and follow move/resize/minimize/restore/close/relaunch over negative coordinates and Windowed/Borderless-style geometry.
5. DPI and monitor computations remain valid for available configurations and explicitly report untested multi-monitor/physical-DPI cases.
6. ARM64 execution has no required x64-only product or test helper.
7. Focused tests pass on the native-ISA ARM64 VM and under x64 emulation where feasible, with deliberate rejection paths passing and physical ARM64/native-x64 gates left open.

## Results

### Verdict

**Invalidated.** Commit `0f23459f660d85113af8c3a4d901cff156a77067` is not acceptable as integrated. Two reproducible runtime defects violate exact-name and event-hook-lifecycle requirements, and its controlled-host discovery is incompatible with the architecture-specific output layout produced by the build/RID lane.

### REV-INT-001: locator still accepts non-exact executable names

- Severity: high.
- Architecture: both; reproduced with an x64 host under ARM64 emulation.
- Root cause: `Bg3WindowLocator.TryGetVerifiedProcessName` calls `Path.GetFileNameWithoutExtension(executablePath)` before `Bg3ProcessNames.IsSupported`. The new matcher correctly rejects `bg3.exe.exe` directly, but the locator converts that image to `bg3.exe` and accepts it. The same composition can convert other final extensions such as `bg3.scr` to the accepted bare name `bg3`.
- Reproduction: an isolated harness copied the controlled host apphost as `bg3.exe.exe`, launched its visible window, and called the production `Bg3WindowLocator`. Output:

  `image=bg3.exe.exe; normalized=bg3.exe; matcher=True; locator-pid=8980; actual-pid=8980`

- Result: the production locator returned the false-positive process/window. The added direct matcher test for `bg3.exe.exe` therefore does not exercise the production normalization path and gives false confidence.
- Required disposition: verify the full executable filename from the trusted image path as exactly `bg3.exe` or `bg3_dx11.exe` before removing any extension, while retaining case-insensitive Windows semantics. Add an end-to-end locator test for double/alternate extensions and lookalike paths.

### REV-INT-002: cross-thread disposal silently leaks both WinEvent hooks

- Severity: high.
- Architecture: both; reproduced in the x64-emulated review process on Windows 11 ARM64.
- Root cause: `Bg3WindowMonitor.Dispose` permits any calling thread, ignores `UnhookWinEvent` failure, and unconditionally clears each hook handle. Windows requires `UnhookWinEvent` to run on the same thread that called `SetWinEventHook`; the current tests never call `Start`, so they do not exercise installation or disposal.
- Reproduction: an isolated harness kept the installing OS thread alive, reflected the two installed handles, invoked `Dispose` on a different OS thread, then asked the original thread to remove the saved handles:

  `installed foreground=0x17901BD; location=0x11F01A7; start-os-thread=3560`

  `dispose-os-thread=11228`

  `original-thread-cleanup foreground=True/error=0; location=True/error=0`

- Result: both original-thread cleanup calls succeeded, proving the cross-thread `Dispose` calls did not remove either hook. The monitor nevertheless marked itself disposed and discarded both handles, preventing retry. This can leave callbacks registered after application teardown and violates deterministic hook cleanup.
- Supporting API contract: Microsoft documents that `UnhookWinEvent` fails from a thread different from the corresponding `SetWinEventHook` call and must be called on the installing thread: <https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-unhookwinevent>.
- Required disposition: marshal cleanup to the installing/message-loop thread or constrain/enforce same-thread lifecycle; check both unhook results, preserve failed handles for a safe retry, and add a real `Start`/cross-thread-dispose regression test.

### REV-INT-003: controlled-host lookup misses integrated architecture output

- Severity: high (matrix CI blocker).
- Architecture: arm64 and x64.
- Root cause: `FindHostOutput` searches:

  `spikes/GameWindowHost/bin/<Configuration>/<TFM>/<RID>`

  The explicit solution platform from the build/RID lane emits:

  `spikes/GameWindowHost/bin/<Architecture>/<Configuration>/<TFM>/<RID>`.

- Reproduction: building the unchanged host with `--configuration Debug -p:Platform=x64` succeeded and emitted:

  `...\bin\x64\Debug\net10.0-windows10.0.26100.0\win-x64\GameWindowHost.exe`

  The worker lookup path was:

  `...\bin\Debug\net10.0-windows10.0.26100.0\win-x64\GameWindowHost.exe`

  The integrated path existed; the worker lookup did not.
- Result: after build/RID integration, both architecture jobs can build the correct host and still fail discovery before any lifecycle assertion. The optional `publish` suffix does not repair the missing architecture directory.
- Required disposition: derive the host output from the same explicit architecture contract or pass an exact validated host path from the build; add an integration test against the final `bin/<arch>/.../<rid>` layout.

### Checks that resisted invalidation

- Focused x64-emulated unit/WPF set passed: 29/29 across process-name matcher, monitor refresh behavior, placement/DPI calculations, and overlay window service.
- Explicit invalid input `BG3_CONTROLLED_HOST_RID=win-x86` was rejected before launch in both theory rows with the intended supported-RID error.
- Owned production P/Invoke handles, hooks, callback context, `WPARAM`, and `LPARAM` remain pointer-sized (`nint`); fixed-width Win32 IDs, flags, coordinates, and `RECT` values remain appropriately 32-bit.
- PE machine checking and combined PE/`IsWow64Process2` labeling correctly distinguish ARM64 images from x64 images and label x64-on-ARM64 as emulated.
- Overlay tests substantiate tool-window/no-activate/topmost style state and no foreground change during placement. The controlled test’s first foreground wait is weak (`foreground == host || foreground != 0` reduces to “any nonzero foreground”), but the later strict host-foreground assertion and separate WPF no-activation test retain useful coverage.
- Move/resize, negative coordinates, minimize/restore, close/relaunch, Windowed/Borderless-style geometry, and bounded waits are covered by the worker’s recorded controlled-host results. This review did not independently reproduce those two full lifecycle rows because the current review checkout lacks an ARM64 SDK/runtime and the integration path defect blocks the final layout.

### Evidence classification and remaining gates

- Review environment: Windows 11 ARM64 Parallels virtual machine on Apple Silicon.
- Review PowerShell: native-ISA ARM64. Installed .NET SDK/test process and executed controlled false-positive host: x64 under ARM64 emulation.
- The 29-test pass and both isolated defect repros are therefore x64-emulated evidence, not native-x64 hardware proof.
- Worker-recorded ARM64 lifecycle results remain native-ISA ARM64 VM evidence, not physical ARM64 evidence; this review did not upgrade their classification.
- Available monitor count remained one in worker evidence. Physical DPI changes, actual multi-monitor movement, physical Windows 11 ARM64 packaged QA, x64 Windows CI, and native-x64 physical hardware validation remain open release gates.
