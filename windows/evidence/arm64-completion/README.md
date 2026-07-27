# Windows ARM64 completion evidence

## Scope and classification

This milestone targets only `arm64`/`win-arm64`. No x64/AMD64 build, review,
package, or test was performed.

All local execution evidence is **native-ISA ARM64 in a Parallels VM** on
Windows 11 ARM64 running on Apple Silicon. It is not physical Windows ARM64
hardware proof. The `mac/` tree remained read-only.

The ARM64 .NET SDK/host was
`C:\Users\jcarbs\AppData\Local\Microsoft\dotnet-arm64\dotnet.exe`. It reported
host architecture `arm64` and RID `win-arm64`.

## Accepted automated result

| Lane | Passed | Failed | Skipped | Evidence |
|---|---:|---:|---:|---|
| Core | 167 | 0 | 0 | `results/arm64-final-core.trx` |
| Infrastructure | 88 | 0 | 0 | `results/arm64-final-infrastructure.trx` |
| App | 37 | 0 | 0 | `results/arm64-final-app.trx` |
| Package | 20 | 0 | 0 | `results/arm64-final-package.trx` |
| Windows | 67 | 0 | 0 | `results/arm64-final-windows-foreground.trx` |
| **Total** | **379** | **0** | **0** | ARM64 testhost throughout |

The Windows suite's first diagnostic run passed 65/67 and timed out only while
Windows foreground policy prevented two synthetic hosts from reacquiring
foreground. The accepted rerun directed physical desktop input to the
unchanged controlled `bg3.exe` and `bg3_dx11.exe` windows and passed 67/67.
`BG3_HEADLESS_CI` was not set. The live OpenRouter canary variable was also
unset, so no provider request was sent.

## Publish and package

- Self-contained publish: `win-arm64`, .NET 10.
- Package identity/version:
  `BG3HonorAssistant.Dev_0.2.0.11_arm64__cq56nxss0c5dp`.
- Installed package: architecture `Arm64`, status `Ok`.
- Installed executable PE machine: `0xAA64`.
- `IsWow64Process2`: process machine `0x0000`, native machine `0xAA64`.
- Recursive inspection: 487 publish PEs, of which 167 are ARM64 native and
  320 are architecture-neutral managed; 486 packaged PEs; result `pass`.
- Architecture record: `arm64-architecture-0.2.0.11.json`.
- Unsigned MSIX SHA-256:
  `164BE28F98634767C0E3C84BA16F92B3CD0EDC6D67C59A99FAE0F3D6B6C19FC9`
  (111,966,587 bytes).
- Development-signed MSIX SHA-256:
  `73D8C205E1ED216C6B369272F17C98B2E4138B812E04A7BDA5F37F5DCBBDCD9B`
  (111,964,547 bytes).

Native ARM64 MakeAppx 10.0.28000.2270 unpacked the exact signed artifact.
Pre-publish and post-unpack validators both passed. The unpacked package held
1,253 files, including 486 `.exe`/`.dll` PE files, ARM64 `e_sqlite3.dll`, 695
WPF-decodable build PNGs, 51 item PNGs, and zero WebP payloads. Product-boundary
validation found no foreign native payload, reparse point, extra executable,
local server/runtime, Python/Node player runtime, service, driver, injection,
save editor, or process-memory component.

## Install, launch, upgrade, tray, and uninstall

1. Development SignTool verification passed with zero warnings or errors.
2. Signed ARM64 package iterations were installed as upgrades through
   0.2.0.11. The package-scoped SQLite state retained the manually created
   runs, run rename, catch-up state, party/build/gear edits, and settings.
3. Immediately before the final uninstall check,
   `LocalState\assistant.sqlite3` was 487,424 bytes with SHA-256
   `0B1F5EDA635785180299C19F629B41B24605E1BBA7FCF1E4D2B19C94A09B0178`.
4. A cold package launch restored the prior hidden-to-tray state. A second
   package activation handed off to the same PID and restored a populated Now
   screen, proving single-instance and initial-tab materialization behavior.
5. Settings startup registration was exercised off -> on -> off. The final
   pre-uninstall state was off.
6. Collapse showed the overlay. The Windows 11 overflow tray menu exposed Show
   Overlay, Open Planner, Open Map, run switching, Steam launch, pet
   visibility, Settings, and Quit. Open Planner restored the existing process;
   Quit ended it cleanly.
7. Uninstall removed the package family and SQLite database. The external
   `BG3HonorAssistant/OpenRouter` Credential Manager target remained.
8. Reinstalling the exact signed 0.2.0.11 MSIX reproduced clean first launch
   with the visible “Well Met, Adventurer” fresh/mid-run fork. The new clean
   database was 69,632 bytes.
9. The final installed package remains registered as `Arm64`/`Ok` and running
   at clean onboarding. All QA-created private keys, trust-store entries,
   public CER exports, dump overrides, and temporary publish/unpack trees were
   removed. The user-owned OpenRouter credential was not removed.

## Credential and OpenRouter observations

Settings showed only that a generic credential existed for
`BG3HonorAssistant/OpenRouter`; the secret was never read, printed, logged,
persisted to SQLite, or packaged. No live provider request was made. The live
canary remains bounded, credential-read-only, opt-in via
`BG3_RUN_LIVE_OPENROUTER=1`, and disabled by default.

The production client uses one direct HTTPS path to `openrouter.ai:443` and the
pinned `google/gemini-3.6-flash` model. Deterministic handlers cover success,
authentication, rate limiting, timeout, cancellation, provider failures,
malformed output, offline failures, response limits, and stale completion
invalidation after cancel, key replacement, or key removal.

## Visual and action evidence

- `screenshots/clean-first-launch-0.2.0.11.png` is the post-uninstall clean
  first-launch proof from the final package.
- `screenshots/final-package-matrix/` contains 57 real packaged-app captures at
  the available 200% DPI for oracle rows 01-14, 16-48, and 51-60.
- Row 15 does not exist in the supplied oracle.
- Rows 49 and 50 are the in-flight and successful live-chat states. They were
  not fabricated or triggered with the user's credential because the live
  canary was not opted in. Their state transitions are covered by deterministic
  OpenRouter/App tests; the matrix index records this limitation.

The captures span the final signed-package integration sequence. When package
QA found a defect, the affected state was fixed and recaptured after the fix:
initial tab materialization, Reference overlay content, roster formatting,
manual point buy, build/item artwork, party-detail reopening, and exact Route
revisit. The final 0.2.0.11 loadout capture proves the separated packaged PNG
resource layout. See `screenshots/final-package-matrix/README.md` and
`defects.md`.

## Independent invalidation reviews

- A reviewer from the OpenRouter lane invalidated product work for
  filter-dependent decision routing, stale undo, unpersisted Explorer
  selection, and ineffective Act revision. The product lane fixed the issues
  and the different-lane re-review accepted it.
- A reviewer from the product lane invalidated persistence for a switch/save
  race, silent/unsealed durable failures, row/payload incoherence, lost corrupt
  bytes, and an unsafe QA root. Persistence fixed the issues and the
  different-lane re-review accepted it.
- A reviewer from the persistence lane invalidated OpenRouter/package work for
  stale noncooperative completions, a renamed-runtime allowlist bypass, and
  possible use of an old key after replacement. The security lane fixed the
  issues and the different-lane re-review accepted it.
- The coordinator then ran an integrated signed-package invalidation pass and
  fixed the seven additional player-flow defects recorded in `defects.md`.
  The final ARM64 suite is 379/379.

The pull request remains a draft because provider-backed UI states were not
live-canary tested without explicit opt-in and because this VM evidence is not
physical Windows ARM64 hardware proof.
