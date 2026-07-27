# ARM64 completion defect record

## Fixed implementation defects

### WIN-PROD-001 — High — Decision completion opened the wrong Route state

- **Reproduction:** complete a decision while Route is filtered to Core or
  Equipment.
- **Root cause:** completion selected from the filtered collection instead of
  restoring All and resolving the exact row.
- **Fix:** restore All, refresh rows, select the exact row, and open its result.
- **Regression test:** Core/product Route tests and packaged Route pass.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-PROD-002 — High — Party undo could restore stale/incomplete state

- **Reproduction:** change roster/build state, perform another mutation, then
  invoke the older undo.
- **Root cause:** undo lacked a full party snapshot and stale-undo invalidation.
- **Fix:** transient full-plan snapshot, restoration banner, and invalidation
  after later party mutations.
- **Regression test:** App controller party/undo tests and packaged undo pass.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-PERSIST-001 — Critical — Run switch could race a queued save

- **Reproduction:** mutate the current run and immediately switch runs.
- **Root cause:** run transitions and durable work lacked one serialized
  barrier.
- **Fix:** ordered durable queue, serialized transition barrier, flush/seal,
  and surfaced exceptions.
- **Regression test:** concurrency/shutdown tests and multi-version upgrade.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-PERSIST-002 — High — Recovery could discard or accept incoherent rows

- **Reproduction:** inject a corrupt snapshot or disagreeing row/payload ids.
- **Root cause:** recovery lacked retained evidence and full coherence checks.
- **Fix:** schema v3 recovery evidence, one-time healing, corrupt-byte
  preservation, and id/name/guide-version validation.
- **Regression test:** repository corruption/recovery/guide tests.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-OR-001 — High — Cancelled/replaced-key work could update UI late

- **Reproduction:** complete a noncooperative request after cancel, close, key
  replace, or key removal.
- **Root cause:** cancellation tokens alone did not invalidate stale callbacks.
- **Fix:** operation generations invalidate old completion paths.
- **Regression test:** OpenRouter/App stale-completion tests.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-PKG-001 — Critical — Renamed executable bypassed package boundary

- **Reproduction:** add a valid ARM64 .NET host named `pythonw.exe`.
- **Root cause:** ISA validation did not prove delivered-file provenance.
- **Fix:** dependency-derived DLL allowlist, exact sole executable and
  package/resource anchors, plus reparse/resource-MZ rejection.
- **Regression test:** adversarial package fixture and clean pre/post unpack.
- **Reviewer result:** different-lane reviewer rejected, then accepted the fix.
- **Residual risk:** low.

### WIN-VIS-001 — Medium — Companion sprite had a black rectangle

- **Reproduction:** compare compact/expanded 0.2.0.0 overlay with the oracle.
- **Root cause:** the Windows WebP/WIC crop path flattened alpha.
- **Fix:** package a lossless RGBA PNG sprite sheet.
- **Regression test:** shared-resource inventory and transparent captures.
- **Reviewer result:** coordinator visual invalidation; fixed in 0.2.0.1.
- **Residual risk:** low.

### WIN-PROD-003 — High — Onboarding roster selection crashed WPF

- **Reproduction:** interact with a roster status ComboBox in onboarding.
- **Root cause:** generated record formatting recursively traversed computed
  `AbilityScores` records, ending in `InsufficientExecutionStackException`.
- **Fix:** bounded `AbilityScores.ToString()` summary.
- **Regression test:** `RecordFormattingDoesNotRecurseThroughComputedAbilityScores`.
- **Reviewer result:** integrated packaged-app invalidation found and rechecked
  the fix.
- **Residual risk:** low.

### WIN-PROD-004 — High — Initial planner tab could be blank

- **Reproduction:** finish onboarding or cold-launch with Now selected.
- **Root cause:** the custom tab template did not materialize initial content
  while onboarding owned first layout.
- **Fix:** reselect/layout the planner tab after load and onboarding.
- **Regression test:** packaged cold restart and same-PID restore show Now.
- **Reviewer result:** integrated package invalidation found and rechecked it.
- **Residual risk:** low.

### WIN-VIS-002 — High — Reference overlay was transparent/empty

- **Reproduction:** select Reference density and collapse.
- **Root cause:** the shared focus/reference panel was visible only for Focus.
- **Fix:** materialize the card for every non-Minimal density.
- **Regression test:** `OverlayWindowPolicyTests` and packaged row 47.
- **Reviewer result:** integrated package invalidation found and rechecked it.
- **Residual risk:** low.

### WIN-PROD-005 — High — Manual build started with illegal point buy

- **Reproduction:** begin a manual plan for a default class; observe 29/27.
- **Root cause:** displayed creation bonuses were treated as point-buy base.
- **Fix:** remove the distinct +2/+1 bonuses to derive the legal base.
- **Regression test:** all default class/custom profiles produce 27 points;
  packaged Bard editor.
- **Reviewer result:** integrated package invalidation found and rechecked it.
- **Residual risk:** low.

### WIN-VIS-003 — Critical — Build/item WebP terminated player flows

- **Reproduction:** select Bard or open a populated loadout in the package.
- **Root cause:** WPF/WIC could not decode the packaged WebPs in this ARM64 VM.
- **Fix:** preserve source WebPs; package derived lossless PNGs from
  `Resources/WindowsPng`; optional decode now degrades to no image.
- **Regression test:** `AssetImageTests`, package tests, recursive inspection,
  and signed 0.2.0.11 loadout/manual-build captures.
- **Reviewer result:** integrated package invalidation reproduced two crashes
  and rechecked the final artifact.
- **Residual risk:** low; the sole zero-byte optional source image remains
  intentionally absent.

### WIN-PROD-006 — Medium — Party member could not reopen after Back

- **Reproduction:** open Tav, press Back, click Tav again.
- **Root cause:** retained list selection suppressed `SelectionChanged`.
- **Fix:** clear selection when returning to the roster.
- **Regression test:** packaged open -> Back -> reopen interaction.
- **Reviewer result:** integrated package invalidation found and rechecked it.
- **Residual risk:** low.

### WIN-PROD-007 — High — Revisit changed the wrong Route step

- **Reproduction:** skip a step, advance, then Revisit from archived detail.
- **Root cause:** focus rejected the skipped row and disposition changed the
  already-advanced current step.
- **Fix:** atomically restore/focus/persist the exact selected step.
- **Regression test:** exact-step controller test and packaged skip -> Revisit.
- **Reviewer result:** integrated package invalidation found and rechecked it.
- **Residual risk:** low.

## Closed evidence gaps

### WIN-QA-001 — Medium — Exhaustive signed-package UI/action matrix

- **Reproduction:** compare the supplied 59-row oracle (row 15 is absent) with
  `screenshots/final-package-matrix/`.
- **Root cause:** the earlier final pass captured only four states after a late
  sprite repair.
- **Fix:** replay the signed integration sequence, capture all 57 non-provider
  rows, record actions, repair each observed regression, and rerun all suites.
- **Regression test:** 57 PNGs, matrix index, 379/379 ARM64 tests, clean final
  first launch, and exact 0.2.0.11 package/resource/loadout proof.
- **Reviewer result:** coordinator integrated invalidation completed; the three
  implementation lanes already had accepted different-lane reviews.
- **Residual risk:** rows 49/50 have deterministic client/decode coverage and
  source/action review but no runtime screenshot because no live canary was
  authorized. Captures span the signed integration sequence and lack embedded
  per-image version metadata. The PR remains draft for these limitations and
  the non-physical-hardware classification.

### WIN-ENV-001 — Informational — QA signing/diagnostic residue

- **Reproduction:** inspect the two QA thumbprints, Temp CERs, dump override,
  and temporary publish/unpack trees.
- **Root cause:** iterative signing and crash diagnosis created local residue.
- **Fix:** delete the exact verified entries after reinstall validation.
- **Regression test:** zero matching certificates in CurrentUser/LocalMachine
  My/Root/TrustedPeople; CERs, dump override, and temporary trees absent;
  installed package remains `Arm64`/`Ok`.
- **Reviewer result:** coordinator cleanup check passed.
- **Residual risk:** none identified. The user-owned OpenRouter credential was
  intentionally retained.

## Remaining evidence limitations

- No physical Windows ARM64 hardware proof; all local results are native-ISA
  ARM64 in a Parallels VM.
- No live OpenRouter UI canary or rows 49/50 screenshots without explicit
  opt-in. No finding is invented for those states.
- The development signature is intentionally untimestamped and not a
  production trust/SmartScreen result.
