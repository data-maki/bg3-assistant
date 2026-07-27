# Windows ARM64 completion evidence

## Scope and classification

This milestone targets only `arm64`/`win-arm64`. No x64/AMD64 build, review,
package, or test was performed.

All local execution evidence is **native-ISA ARM64 in a Parallels VM** on
Windows 11 ARM64 running on Apple Silicon. It is not physical Windows ARM64
hardware proof.

Opening the draft PR initially triggered the repository's historical dual-RID
matrix. Run `30259250896` was cancelled while the x64 job was still in
`setup-dotnet`; its restore, build, test, publish, package, inspection, and
upload steps were all skipped. The PR workflow was then scoped to the ARM64
entry for this milestone.

The ARM64 .NET SDK/host was
`C:\Users\jcarbs\AppData\Local\Microsoft\dotnet-arm64\dotnet.exe`. It reported
host architecture `arm64` and RID `win-arm64`.

## Accepted automated result

| Lane | Passed | Failed | Evidence |
|---|---:|---:|---|
| Core | 165 | 0 | `results/arm64-final-core.trx` |
| Package | 20 | 0 | `results/arm64-final-package.trx` |
| Infrastructure | 88 | 0 | `results/arm64-final-infrastructure.trx` |
| Windows | 67 | 0 | `results/arm64-final-windows-foreground.trx` |
| App | 30 | 0 | `results/arm64-final-app.trx` |
| **Total** | **370** | **0** | ARM64 testhost throughout |

The Windows integration lane was first launched from a headless PTY while the
packaged application and later the shell owned foreground activation. Those
diagnostic runs passed 65/67 and timed out only at the synthetic host's strict
foreground assertion. They are retained under
`results/diagnostic-foreground-lock/`. With real foreground input directed to
the controlled `bg3.exe`/`bg3_dx11.exe` windows, the unchanged suite passed
67/67 in four seconds. GitHub's hosted ARM64 runner cannot accept foreground
activation even with injected input, so CI sets `BG3_HEADLESS_CI=1` to skip
only the strict foreground reacquisition while retaining the remaining
geometry, style, detection, movement, resize, minimize/restore, and lifecycle
assertions. The strict interactive path remains mandatory and green locally.

## Publish and package

- Self-contained publish: `win-arm64`, .NET 10.
- Package identity/version:
  `BG3HonorAssistant.Dev_0.2.0.1_arm64__cq56nxss0c5dp`.
- Package status after install: `Ok`; package architecture: `Arm64`.
- Installed executable PE machine: `0xAA64`.
- `IsWow64Process2`: process machine `0x0000`, native machine `0xAA64`.
- Recursive inspection: 487 publish PEs, of which 167 are ARM64 native and
  320 are architecture-neutral managed; 486 packaged PEs; result `pass`.
- Architecture record: `arm64-architecture-0.2.0.1.json`.
- Unsigned MSIX SHA-256:
  `3C991C95034EBB42642B00742F6D517C9E6CBC645D1DEC7B31AFB2D4254D756E`
  (94,174,266 bytes).
- Development-signed MSIX SHA-256:
  `436C35CAFB1DEADE0D06A68D61645F81C6B60F8674EA209A3CAB1693BEEB623C`
  (94,172,155 bytes).

The package was validated before pack and after unpack. The product-boundary
validator derives its allowed DLLs from the selected `win-arm64` dependency
target, permits only exact product/package/resource anchors, rejects reparse
points and executable content under Resources, and rejected an adversarial
ARM64 runtime renamed to `pythonw.exe`.

## Install, launch, upgrade, and uninstall

1. Development-signing verification passed with the temporary
   `CN=BG3HonorAssistant Development` certificate.
2. Signed 0.2.0.0 installed and reported `Arm64`/`Ok`.
3. Clean first launch created `LocalState\assistant.sqlite3` and displayed
   fresh onboarding.
4. Fresh onboarding completed with Honour Mode, next-three spoiler policy,
   guide-only mode, and the default party.
5. Expanded and compact overlay, tray restoration, Now, Route, Party, Loadout,
   Act, and Settings surfaces were opened. Tray `Quit` exited the process
   cleanly.
6. The pre-upgrade SQLite database was 81,920 bytes with SHA-256
   `94C61526F1499AA8A4E7FCD0AF4D155459D1C99123484762F596897140399AA5`.
7. Signed 0.2.0.1 upgraded in place. The database length and SHA-256 were
   unchanged, onboarding did not replay, and the installed process remained
   native ARM64.
8. Uninstall removed the package and LocalState. No BG3 startup entry was
   registered. The user-owned `BG3HonorAssistant/OpenRouter` generic
   credential remained, as expected for Credential Manager data outside the
   package sandbox.
9. A second clean install reproduced fresh onboarding and provided the final
   screenshots, after which the package and temporary trust entry were removed.

The development certificate's private key and every temporary trust-store
entry were removed. A public `.cer` export remains in the user's Temp directory
because the executor blocked deletion outside the workspace; it contains no
private key and is no longer trusted.

## Credential and OpenRouter observations

Settings showed only that a generic credential existed for
`BG3HonorAssistant/OpenRouter`, with username `OpenRouter`; the secret was
never read, printed, logged, persisted to SQLite, or packaged. No live provider
request was made. The live canary remains bounded, credential-read-only,
opt-in via `BG3_RUN_LIVE_OPENROUTER=1`, and disabled by default.

The production client uses one direct HTTPS path to `openrouter.ai:443` and the
pinned `google/gemini-3.6-flash` model. Deterministic tests cover success,
authentication, rate limiting, timeout, cancellation, provider failures,
malformed output, offline failures, response limits, and stale completion
invalidation after cancel, key replacement, or key removal.

## Final visual samples

- `screenshots/12-final-clean-first-launch.png`
- `screenshots/11-upgraded-overlay-transparent.png`
- `screenshots/13-final-now.png`
- `screenshots/14-final-settings.png`

The first visual pass exposed black rectangles behind the WebP sprite because
the Windows WIC path flattened alpha. The final package uses a lossless RGBA
PNG sprite sheet and the final captures show transparent companion artwork.
Pre-fix captures are retained only as diagnostic evidence under
`screenshots/diagnostic-pre-fix-webp-alpha/`.

## Independent invalidation reviews

- A reviewer from the OpenRouter lane invalidated the product lane for
  filter-dependent decision routing, stale undo, unpersisted Explorer
  selection, and ineffective Act revision. The product lane fixed each issue;
  focused Core and product tests passed.
- A reviewer from the product lane invalidated persistence for a switch/save
  race, silent/unsealed durable failures, row/payload incoherence, lost corrupt
  bytes, and an unsafe QA root. Persistence fixed each issue; repository,
  AppData, and App tests passed.
- A reviewer from the persistence lane invalidated OpenRouter/package work for
  stale noncooperative completions, a renamed-runtime allowlist bypass, and
  possible use of an old key after replacement. The security lane fixed each
  issue; OpenRouter, package, credential, and canary tests passed.

See `defects.md` for exact defect records and residual risk.
