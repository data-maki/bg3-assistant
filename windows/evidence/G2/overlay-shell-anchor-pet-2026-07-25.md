# Overlay shell, anchor, and pet - 2026-07-25

## Scope

This evidence covers the Windows tray command model, focus/minimal overlay surfaces,
normalized drag-anchor persistence, and the Twilight Cleric pet. It uses the controlled
x64 `bg3.exe` test host. Baldur's Gate 3 was not installed or launched, and this does not
claim actual renderer, gameplay, or game-input compatibility.

## Tray command model

The production `NotifyIcon` menu now exposes the Mac-oracle commands:

- Show Overlay
- Open Planner
- Open Map
- a dynamically named run submenu with checked active run and switch actions
- Launch Baldur's Gate 3
- Hide Pet / Show Pet
- Settings
- Quit

`TrayMenuTests` constructs the real production menu, refreshes two runs, verifies checked
state and dynamic pet label, and invokes every menu item to prove it reaches its owned
action. The package source contract verifies the same inventory and the absence of a
global hotkey. A visible-shell NotifyIcon interaction remains part of the clean-VM UI
matrix.

## Deterministic pet

The Mac `PetAnimationModel` behavior is ported as pure Core code:

- six authored idle timings;
- five authored jump-intro timings;
- rows 9/10 for all 16 pointer-look directions;
- pointer dead zone; and
- reduced-motion behavior.

Sixteen unit cases prove the timing boundaries, direction mapping, idle/resting state,
and reduced-motion semantics. The product uses Windows' native image pipeline to decode
the committed 1536×2288 `twilight-cleric.webp`, then crops the same 192×208 cells as the
Mac oracle. Seven Windows app cases prove representative first/middle/final frames and
invalid-coordinate rejection. Decode failure degrades to a static local `H` glyph
without downloading or executing anything.

The minimal WPF surface exposes `Twilight Cleric companion`, `Resting`/`Awake` item
status, and `Hover to wake the companion` to UI Automation. It includes a separate
Open-assistant button so the non-button pet region remains draggable.

## Focus surface

A real product UI Automation read found the focus card and all required visible
shortcuts:

- `Open route`
- `Ask typed chat`
- `Mark current task complete`
- `Collapse overlay`

The focus card also exposed the current action, `L1+`, area/danger, and avoid text. Its
owned context menu contains snooze, mute, pin, and all three density commands. Route and
Ask deliberately activate the planner; task, snooze, mute, pin, density, collapse, and
drag remain in the passive overlay window.

## Controlled-host drag and focus result

Machine: current Windows 11 development machine, 200% scale, one physical display.  
Host: exact-name controlled x64 `bg3.exe`, window bounds
`240,240,2560,1440`.

1. A real pointer click on Collapse changed the product overlay to its 92×92 DIP minimal
   surface, observed as 184×184 physical pixels.
2. Foreground before and after Collapse remained the controlled host HWND.
3. A real pointer drag began on the non-button pet surface and ended 120 pixels left and
   80 pixels up.
4. Overlay bounds changed from `2584,837,184,184` to `2464,757,184,184`.
5. Foreground before and after the drag was the same controlled host HWND.
6. The app persisted the normalized anchor to SQLite preferences.
7. After terminating and restarting the product while the controlled host remained
   present, the overlay returned to exactly `2464,757,184,184`; the pet remained exposed
   as `Resting`.

Automated placement cases separately prove normalized-anchor round trip and clamping on
negative-coordinate monitors. Pixel rounding is bounded to one physical pixel.

Relevant code and tests:

- [`../../src/BG3HonorAssistant.Core/Overlay/PetAnimationModel.cs`](../../src/BG3HonorAssistant.Core/Overlay/PetAnimationModel.cs)
- [`../../src/BG3HonorAssistant.Windows/Overlay/OverlayPlacement.cs`](../../src/BG3HonorAssistant.Windows/Overlay/OverlayPlacement.cs)
- [`../../src/BG3HonorAssistant.Windows/Overlay/OverlayWindowService.cs`](../../src/BG3HonorAssistant.Windows/Overlay/OverlayWindowService.cs)
- [`../../src/BG3HonorAssistant.App/OverlayWindow.xaml`](../../src/BG3HonorAssistant.App/OverlayWindow.xaml)
- [`../../src/BG3HonorAssistant.App/OverlayCoordinator.cs`](../../src/BG3HonorAssistant.App/OverlayCoordinator.cs)
- [`../../src/BG3HonorAssistant.App/TrayMenu.cs`](../../src/BG3HonorAssistant.App/TrayMenu.cs)
- [`../../tests/BG3HonorAssistant.Core.Tests/Overlay/PetAnimationModelTests.cs`](../../tests/BG3HonorAssistant.Core.Tests/Overlay/PetAnimationModelTests.cs)
- [`../../tests/BG3HonorAssistant.Windows.Tests/Overlay/OverlayPlacementTests.cs`](../../tests/BG3HonorAssistant.Windows.Tests/Overlay/OverlayPlacementTests.cs)
- [`../../tests/BG3HonorAssistant.App.Tests/PetSpriteLoaderTests.cs`](../../tests/BG3HonorAssistant.App.Tests/PetSpriteLoaderTests.cs)
- [`../../tests/BG3HonorAssistant.App.Tests/TrayMenuTests.cs`](../../tests/BG3HonorAssistant.App.Tests/TrayMenuTests.cs)

## Evidence boundary

This is a one-display 200% controlled-host pass. The physical two-monitor and 100%/150%
matrix, visible NotifyIcon clean-VM interaction, high-contrast/reduced-motion UI
inspection, and production-signed package remain outstanding. Live BG3 is intentionally
not a release gate.
