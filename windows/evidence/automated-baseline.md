# Automated baseline

Date: 2026-07-25  
Oracle commit: `591e2331d45cd60505430610c24fe63b36c7293d`

## Commands and results

```powershell
dotnet restore windows/BG3HonorAssistant.slnx --locked-mode --force-evaluate -m:1 -nr:false
dotnet build windows/BG3HonorAssistant.slnx --configuration Release --no-restore -m:1 -nr:false
dotnet test <each test project> --configuration Release --no-build --no-restore -m:1 -nr:false
dotnet list windows/BG3HonorAssistant.slnx package --vulnerable --include-transitive
```

- Restore: pass; lock files generated for all projects.
- Release build: pass with 0 warnings and 0 errors.
- Tests: 267 pass, 0 fail, 0 skipped.
  - App: controller initialization, run switching/mutation, recovery, imported-build
    persistence/assignment, and restart behavior (8).
  - Core: all 41 live Mac behavior tests (with the reviewed Windows MVP adaptations
    documented in `G1/mac-oracle-test-port-2026-07-25.md`) plus 38 Windows oracle,
    compatibility, and domain tests covering Swift date/JSON snapshots, current-goal
    priority, route/activity derivation, roster and party-plan invariants, and complete
    ability progression/source rules, plus typed-chat prompt/scope/source/schema
    contracts (140 total).
  - Infrastructure: SQLite persistence/migration/recovery/resource tests, shared-guide
    decode and lossless typed round trip, direct OpenRouter request/error/response
    contracts, public-network policy, redirect and DNS-rebinding defense, bounded
    HTML/PDF/text loading, and structured build-import validation (76).
  - Windows: 35 process-name, controlled exact-name x64 game-window, game-monitor,
    raw/live-WPF HWND overlay, 100/150/200% DPI math, overlay-placement, single-instance,
    Credential Manager, package identity, startup-fallback, and opt-in live OpenRouter
    canary tests. The ordinary baseline does not contact OpenRouter.
  - Package/resources: 8 shared guide/media inventory, MSIX contract, MVP-exclusion,
    no-elevation, executable DPI-awareness, single text-only HTTP surface, and
    no-secret-persistence tests.
- Machine-readable results:
  [`App`](automated-results/BG3HonorAssistant.App.Tests-2026-07-25.trx),
  [`Core`](automated-results/BG3HonorAssistant.Core.Tests-2026-07-25.trx),
  [`Infrastructure`](automated-results/BG3HonorAssistant.Infrastructure.Tests-2026-07-25.trx),
  [`Windows`](automated-results/BG3HonorAssistant.Windows.Tests-2026-07-25.trx), and
  [`Package`](automated-results/BG3HonorAssistant.Package.Tests-2026-07-25.trx).
- Vulnerability audit: no vulnerable direct or transitive packages reported.
- Runtime SQLite assertion: loaded SQLite is at least 3.50.2.
- Development packaging: MakeAppx 10.0.28000.2270 accepted the manifest and packed a
  self-contained x64 MSIX. The artifact is intentionally unsigned and is not release evidence.

## Evidence boundary

This baseline is automated evidence only. It does not by itself pass G0 or any complete
parity row. The one-display controlled-host result is recorded in
`G0/controlled-window-matrix-2026-07-25.md`.
Capture and speech are approved MVP exclusions in `mvp-scope-2026-07-25.md`.
The remaining physical display/DPI matrix, production-signed installation, update,
uninstall, Defender, and clean-machine evidence remains outstanding.
