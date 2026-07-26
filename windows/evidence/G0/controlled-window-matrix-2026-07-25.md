# Controlled game-window matrix - 2026-07-25

## Scope

This is the approved replacement for live BG3 installation and renderer testing in the
Windows MVP. The test infrastructure builds a WPF x64 host, stages it under the exact
process-image names `bg3.exe` and `bg3_dx11.exe`, and presents controlled borderless-style
and windowed-style top-level windows. The host visibly identifies itself as test
infrastructure and contains no game code.

Source:

- [`../../spikes/GameWindowHost`](../../spikes/GameWindowHost)
- [`../../tests/BG3HonorAssistant.Windows.Tests/GameDetection/ControlledGameWindowIntegrationTests.cs`](../../tests/BG3HonorAssistant.Windows.Tests/GameDetection/ControlledGameWindowIntegrationTests.cs)
- [`results/controlled-window-2026-07-25.trx`](results/controlled-window-2026-07-25.trx)

## Environment

- Oracle commit: `591e2331d45cd60505430610c24fe63b36c7293d`
- Windows: Windows 11 Pro 10.0.26200, build 26200
- Physical host architecture reported by the environment: ARM64
- Test runner: x64 .NET 10.0.10
- Controlled host PE machine: `0x8664` (`AMD64`)
- Connected displays: one
- Live window DPI: 192 (200%)

## Automated result

Command:

```powershell
dotnet test tests/BG3HonorAssistant.Windows.Tests/BG3HonorAssistant.Windows.Tests.csproj `
  -c Release --no-build --no-restore `
  --filter FullyQualifiedName~ControlledGameWindowIntegrationTests
```

Result: 2 passed, 0 failed.

| Process image | Geometry | Initial detected bounds | Moved/resized bounds | DPI | Result |
|---|---|---|---|---:|---|
| `bg3.exe` | Borderless-style | `(250,240)-(2790,1670)` | `(-1790,128)-(110,1198)` | 192 | Pass |
| `bg3_dx11.exe` | Windowed-style | `(251,240)-(2789,1669)` | `(-1789,128)-(109,1197)` | 192 | Pass |

For each executable, the integration test verifies:

- exact process-image matching through the production locator;
- largest visible top-level window detection and physical DWM bounds;
- x64 host identity;
- movement, resize, and negative-coordinate recovery;
- passive topmost overlay positioning without foreground theft;
- deliberate activation only after removing `WS_EX_NOACTIVATE`, followed by restoration
  of the passive contract;
- minimize produces a no-target state;
- restore reacquires the target;
- close publishes a no-target state; and
- temporary staged executables are removed.

The production size calculation has explicit 96/144/192 DPI cases (100/150/200%). The
live run above physically exercised 192 DPI only.

## Evidence boundary

This is not Baldur's Gate 3. It does not claim renderer, gameplay, game-input, Steam,
DX11, Vulkan, or live-game compatibility. Negative coordinates were exercised on a
single connected display; this is not a physical two-monitor transition. Physical
100%, 150%, two-monitor, and native-x64-machine runs remain outstanding G0 matrix work.
