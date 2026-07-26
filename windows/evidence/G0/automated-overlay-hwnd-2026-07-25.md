# Automated overlay HWND evidence — 2026-07-25

## Environment

- Oracle commit: `591e2331d45cd60505430610c24fe63b36c7293d`
- Windows: Windows 11 Pro 10.0.26200, build 26200
- Host architecture: ARM64
- Harness target: x64, .NET 10 WPF

## Result

The compiled `spikes/OverlayHarness` was launched and its top-level HWND was enumerated
from a separate PowerShell process. The window titled `BG3 Overlay Harness` reported:

- visible: yes
- `WS_EX_TOOLWINDOW`: set
- topmost band / `WS_EX_TOPMOST`: set
- `WS_EX_NOACTIVATE`: set
- foreground window: no

An initial live HWND test caught that writing the topmost bit alone did not move the window
into the topmost band. `OverlayWindowService.Configure` now calls
`SetWindowPos(HWND_TOPMOST, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)`, and the live
adapter test verifies the corrected behavior.

Automated tests additionally create real Win32 HWNDs to verify passive-to-interactive style
transitions, negative-coordinate placement, physical DPI sizing, and foreground preservation.
An STA WPF test now applies the adapter during `SourceInitialized`, shows the real WPF
window, pumps it to application-idle, and verifies `WS_EX_TOOLWINDOW`, `WS_EX_TOPMOST`,
`WS_EX_NOACTIVATE`, and an unchanged foreground HWND. This specifically covers WPF's
window-presentation lifecycle rather than inferring it from a raw Win32 test HWND.
Game-window monitoring uses `EnumWindows`, `GetWindowThreadProcessId`, visible HWND filtering,
`QueryFullProcessImageNameW` with only `PROCESS_QUERY_LIMITED_INFORMATION`, narrowly scoped
out-of-context foreground/location WinEvents, and a two-second recovery poll.

The subsequent exact-name controlled-host run is recorded separately in
[`controlled-window-matrix-2026-07-25.md`](controlled-window-matrix-2026-07-25.md).

## Evidence boundary

This proves the harness HWND contract on this machine. It does not prove BG3 rendering,
game input preservation, native x64 hardware, physical multiple monitors, physical 100/150%
DPI, or DX11/Vulkan behavior. Those matrix entries remain pending and G0 is not passed.
