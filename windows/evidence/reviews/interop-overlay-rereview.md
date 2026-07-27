# Interop and overlay independent re-review

Commit under review: `cdecb36`

## Pre-experiment Q/A

### Hypothesis

The follow-up may close the previously reported defects in focused unit tests while still failing at one of the real boundaries: production process-image identity, WinEvent unhooking on the installing thread, or controlled-host discovery under the integrated `bin/<arch>/<config>/<TFM>/<rid>` layout. Adversarial lifecycle, path, and architecture inputs may expose incomplete fixes.

### Evidence available before testing

- The commit adds exact executable-image validation to the production locator.
- The commit changes WinEvent-hook disposal to coordinate with the hook-installing thread.
- The commit extends controlled-host lookup and adds focused process-name, monitor, and integration tests.
- Prior review requested independent invalidation of image lookalikes, cross-thread disposal, and integrated RID host lookup.

### Unknowns

- Whether prior exact-image lookalikes are rejected through the production locator, including case, extension, ambiguous/malicious path, access-denied, and early-exit variants.
- Whether installing-thread and cross-thread disposal actually unhook on the owner thread, including repeated disposal, partial unhook failure, owner-thread disappearance, and callbacks after disposal.
- Whether controlled-host discovery finds only the requested architecture in integrated output and rejects a conflicting PE.
- Whether architecture inputs outside exactly `arm64` and `x64` are rejected.
- Whether foreground/focus and geometry behavior remains correct across move, resize, minimize, restore, close, and relaunch.
- What can be demonstrated on this machine as native-ISA ARM64 VM execution versus x64-on-ARM64 emulation.

### Acceptance tests

1. Reproduce the prior exact-image lookalikes through the production locator and test path case/extension variants, malicious ambiguity, access denied, and early process exit.
2. Exercise installing-thread and cross-thread WinEvent disposal and verify unhook thread identity; include idempotence, partial failure, owner-thread disappearance, and callback-after-dispose.
3. Exercise integrated `bin/<arch>/<config>/<TFM>/<rid>` controlled-host lookup with a conflicting PE payload and rejected architecture inputs.
4. Run focused x64 tests under emulation and, where feasible, native-ISA ARM64 VM controlled hosts.
5. Recheck foreground/no-focus-theft and window geometry lifecycle behavior.
6. State whether each prior invalidation closes. Keep physical Windows 11 ARM64 and native-x64 hardware as explicit release gates.

## Environment labels

- **Native-ISA ARM64 VM:** Windows 11 ARM64 in Parallels on Apple Silicon. This is not physical ARM64 hardware.
- **Emulated x64:** x64 .NET/process execution on the ARM64 VM.
- **x64 CI:** separate x64 Windows runner evidence; not native-x64 physical hardware proof.
- **Untested release gates:** physical Windows 11 ARM64 and native-x64 physical hardware.

## Experiments and results

### Environment

- Windows `10.0.26200`; PowerShell reported OS architecture ARM64, process
  architecture ARM64, and 8-byte pointers.
- `Win32_ComputerSystem` reported `Parallels ARM Virtual Machine`,
  `Parallels International GmbH.`, and `HypervisorPresent=True`.
- The installed .NET SDK/host was 10.0.302/10.0.10 x64 with RID `win-x64`.
  Therefore every xUnit run below was **x64-on-ARM64 emulated**, even when it
  launched an independently built host.
- The focused host read from the PE header as machine `0x8664` (x64).

### Commands and outcomes

1. Locked restore:
   `dotnet restore windows/tests/BG3HonorAssistant.Windows.Tests/BG3HonorAssistant.Windows.Tests.csproj --locked-mode`
   passed.
2. Focused process-name, monitor, placement, and overlay-service run:
   40 passed, 0 failed. This included the real WinEvent-hook test that installs
   on a dedicated thread, rejects cross-thread disposal, then successfully
   disposes on the installing thread.
3. Focused production-locator lookalikes and host-layout run:
   5 passed, 0 failed. Visible x64-emulated hosts named `bg3.exe.exe`,
   `bg3.scr`, and `bg3_dx11.com` were rejected by `Bg3WindowLocator`.
   Synthetic integrated architecture-first lookup resolved
   `bin/arm64/Debug/net10.0-windows10.0.26100.0/win-arm64`, and a conflicting
   x64 PE in a neighboring legacy candidate caused explicit rejection.
4. Explicit `BG3_CONTROLLED_HOST_RID=win-x64` lifecycle run:
   2 passed, 0 failed. The x64 PE host was **emulated x64 on ARM64**, not
   native-x64 hardware. Both `bg3.exe` borderless-style and `bg3_dx11.exe`
   windowed-style cases covered detection, bounds/DPI, negative coordinates,
   move/resize, overlay follow, passive/interactive styles, no-focus-theft,
   minimize/restore, close/relaunch, and final disappearance.
5. Expected-negative `BG3_CONTROLLED_HOST_RID=win-x86` run:
   both selected cases stopped before launch with
   `supports exactly win-arm64 and win-x64`; command exit was 1 as expected.
   No x86 host was launched.

### Adversarial review

- **Path/name variants:** the trusted `QueryFullProcessImageNameW` result is
  reduced with `Path.GetFileName`, then compared ordinally and
  case-insensitively against only `bg3.exe` and `bg3_dx11.exe`. Case variants
  therefore pass; bare names, alternate/double extensions, whitespace,
  full-path input to the public matcher, suffixes, and Unicode/path ambiguity
  do not become accepted names. Any executable genuinely named `bg3.exe` is
  intentionally in scope regardless of install directory; path provenance is
  not a product requirement.
- **Access denied / early exit:** `OpenProcess` or
  `QueryFullProcessImageNameW` failure returns a non-candidate. The unmanaged
  enumeration callback also catches exit/protected-process races so exceptions
  do not cross the callback boundary. These branches were confirmed by source
  review; this commit does not provide a deterministic injection seam for a
  separate access-denied/exit-race test.
- **Disposal and callbacks:** successful disposal is idempotent.
  Cross-thread disposal throws before the timer or hook handles are changed,
  allowing the installing-thread retry exercised above. Successful unhooks
  clear handles; failed unhooks retain their handles and aggregate errors, so a
  same-thread retry is possible. A late callback calls `Refresh`, which checks
  `disposed` before locating or publishing. Partial native-unhook failure and
  owner-thread disappearance could not be deterministically forced through the
  static native surface and remain unautomated. If the owner thread disappears,
  another thread cannot legally unhook these WinEvent hooks; the product must
  preserve its UI-thread start/dispose lifecycle.
- **Host lookup:** all existing integrated/publish/legacy candidates are PE
  inspected before the preferred candidate is returned, so a conflicting
  neighbor cannot be silently selected. PE parsing reads the machine field but
  does not independently validate DOS/PE signatures; build/package inspection
  remains the authoritative artifact check.

## Independent disposition

| Prior invalidation | Result | Independent basis | Residual risk |
| --- | --- | --- | --- |
| `REV-INT-001` production locator accepted alternate/double extensions | **Closed** | Three prior visible lookalikes were reproduced through the production locator and rejected; strict unit variants passed; trusted image-path code was reviewed. | Deterministic access-denied and process-exit race injection is absent. |
| `REV-INT-002` cross-thread disposal silently leaked WinEvent hooks | **Closed for the reported failure** | Real hooks were installed on a dedicated OS thread; cross-thread disposal failed before state mutation; owner-thread disposal then succeeded. Handle retention and retry logic resist partial failure by inspection. | Partial native-unhook failure, owner-thread disappearance, and late native callback timing lack injectable regression tests. Product start/dispose must remain on its WPF UI thread. |
| `REV-INT-003` integrated host lookup missed `bin/<arch>/.../<rid>` | **Closed** | Architecture-first synthetic lookup passed and an adjacent conflicting PE was rejected. | The isolated branch still has x64-hard-coded build props/spike configuration; the integrated build lane must supply real dual-RID outputs. |

No new reproducible source defect was established in `cdecb36`. The unautomated
native failure modes above are recorded as residual test risks, not claimed as
passes.

## Architecture evidence and release gates

- This re-review provides **emulated x64 on an ARM64 VM** evidence only.
- A native-ISA ARM64 controlled-host rerun was not performed in this isolated
  follow-up branch: its pre-integration build props and spike project remain
  x64-hard-coded, and this evidence-only review did not edit source/build files.
  Prior lane evidence is not relabeled as an independent rerun.
- No physical Windows 11 ARM64 claim is made.
- No native-x64 physical hardware claim is made.
- Physical Windows 11 ARM64 packaged-product validation, x64 Windows CI
  execution, and native-x64 physical validation remain explicit gates. The VM
  lifecycle tests do not replace install/upgrade/uninstall, packaged process,
  credentials/startup/tray, or real multi-monitor validation.
