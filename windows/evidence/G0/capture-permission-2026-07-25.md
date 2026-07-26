# Capture and consent evidence — 2026-07-25

> Historical development research only. Screenshot capture is an approved Windows MVP
> exclusion, and the capture product code, UI, harness, and package capability have been
> removed. This record is not a release gate or parity claim; see
> `../mvp-scope-2026-07-25.md`.

## Environment

- Windows: Windows 11 Pro 10.0.26200, build 26200
- Host architecture: ARM64
- Harness target: x64, .NET 10 WPF
- Graphics target: generic WPF window; BG3 is not installed on this machine
- Color mode tested: SDR only

## Consent and cancellation result

UI Automation invoked the enabled `Choose BG3 window…` button only after the harness
was foreground. Windows opened its secure picker as an `ApplicationFrameWindow` titled
`Capture with BG3 Secure Capture Harness`.

Pressing Escape canceled the system picker. The harness remained alive and reported:

`Picker canceled. No capture item or pixels were retained.`

No picker or capture is started during harness launch.

The picker service now permits exactly three user-initiated attempts per service/session.
After the third invocation it disables capture with an explicit message while typed chat
and the local guide remain available. Automated tests cover the exact limit and ensure
additional attempts do not consume or reopen capture. No global input synthesis, Snipping
Tool shortcut, automatic clipboard read, or clipboard persistence is used.

## One-frame result

The same secure picker was invoked again and its accessible list was used to select the
generic `BG3 Secure Capture Harness` WPF window. The Windows `AcceptButton` was disabled
until a target was selected and enabled afterward. The harness reported:

`Captured one frame from “BG3 Secure Capture Harness” (1098×649, 80,462 JPEG bytes).
No extended-range pixels were present.`

The implementation uses a one-buffer `Direct3D11CaptureFramePool`, keeps
`IsBorderRequired=true`, requests `R16G16B16A16_FLOAT`, maps one staging texture, applies
an explicit extended-range shoulder and linear-to-sRGB conversion, JPEG-encodes in memory,
then disposes the frame, session, pool, D3D context, and device. Automated fixtures verify
the SDR channel conversion, HDR shoulder behavior, invalid buffer rejection, and live
hardware-to-WinRT D3D device projection.

The first consent run found and corrected a C#/WinRT owner-HWND interop defect:
`GraphicsCapturePicker` now uses `picker.As<IInitializeWithWindow>()`. The corrected cancel
and one-frame runs completed without terminating the process.

## Evidence boundary

This proves explicit picker invocation, visible Windows consent UI, cancellation safety,
one generic SDR window frame, in-memory JPEG encoding, and session teardown on this machine.
It does not prove BG3 selection, overlay exclusion from a BG3 item, DX11/Vulkan, minimized or
closed targets, Windows HDR, 100/150/200% DPI, multiple monitors, denial by privacy or
enterprise policy, or native x64 hardware. Those checks remain pending and G0 is not passed.
