# ARM64 completion defect record

## Fixed defects

### WIN-PROD-001 — High — Decision completion opened the wrong Route state

- **Reproduction:** complete a decision while Route is filtered to Core or
  Equipment.
- **Root cause:** completion selected from the filtered collection rather than
  restoring All and resolving the exact route row.
- **Fix:** force All, refresh rows, select the exact `RoutePlannerRow`, and open
  outcome detail.
- **Regression test:** focused Core/product route tests; included in 165/165
  Core and 30/30 App results.
- **Reviewer result:** original reviewer rejected; different-lane re-review
  accepted after the fix.
- **Residual risk:** low; final interactive recapture of every decision variant
  remains part of `WIN-QA-001`.

### WIN-PROD-002 — High — Party undo could restore stale or incomplete state

- **Reproduction:** change roster/build state, perform another party mutation,
  then invoke the older undo.
- **Root cause:** undo did not retain the full party plan and was not invalidated
  by later party mutations.
- **Fix:** transient full-plan undo snapshot, active-party/build restoration,
  visible undo banner, and stale-undo invalidation.
- **Regression test:** App controller party/undo tests.
- **Reviewer result:** rejected before fix; accepted after focused 31/31 Core
  and product checks.
- **Residual risk:** low.

### WIN-PERSIST-001 — Critical — Run switch could race a queued save

- **Reproduction:** mutate the current run and immediately switch runs while a
  save is queued.
- **Root cause:** run transitions and durable producer work did not share a
  serialized barrier.
- **Fix:** ordered durable queue, serialized run transition barrier,
  `FlushAsync`, producer-sealed `SealAndFlushAsync`, and surfaced exceptions.
- **Regression test:** controller/repository concurrency, flush, and shutdown
  tests; packaged tray quit and byte-stable upgrade observation.
- **Reviewer result:** product reviewer rejected; accepted after the fix.
- **Residual risk:** low.

### WIN-PERSIST-002 — High — Recovery could discard evidence or accept incoherent rows

- **Reproduction:** inject a corrupt active snapshot, or a row whose id/name
  disagrees with its payload.
- **Root cause:** recovery lacked retained rejected evidence and complete
  row/payload coherence checks.
- **Fix:** schema v3 `recovery_evidence`, one-time healing, preservation of
  corrupt rows, and id/name/guide-version coherence validation.
- **Regression test:** infrastructure repository and guide-version tests.
- **Reviewer result:** rejected before fix; accepted after repository/guide
  suites passed.
- **Residual risk:** low.

### WIN-OR-001 — High — Cancelled or replaced-key operations could update UI late

- **Reproduction:** use a noncooperative HTTP stub, cancel or replace/remove
  the key, then complete the old request.
- **Root cause:** cancellation tokens alone could not prevent stale completion
  callbacks.
- **Fix:** operation generations invalidate completion after cancel, close,
  save/replace, or remove; active buttons switch to Cancel.
- **Regression test:** OpenRouter client and App stale-completion tests.
- **Reviewer result:** persistence reviewer rejected; accepted after 27/27
  OpenRouter tests and 30/30 App tests.
- **Residual risk:** low.

### WIN-PKG-001 — Critical — Renamed executable payload bypassed the package boundary

- **Reproduction:** copy a valid ARM64 .NET host into the package as
  `pythonw.exe`.
- **Root cause:** architecture validation proved ISA but not delivered-file
  provenance.
- **Fix:** dependency-derived DLL allowlist, exact sole executable and
  package/resource anchors, reparse-point rejection, and resource MZ rejection.
- **Regression test:** package adversarial test rejects the renamed host; clean
  packed/unpacked ARM64 package passes.
- **Reviewer result:** persistence reviewer rejected; accepted after 20/20
  package tests.
- **Residual risk:** low.

### WIN-VIS-001 — Medium — Companion sprite rendered with a black rectangle

- **Reproduction:** launch 0.2.0.0 and compare compact/expanded overlay with
  screenshot 46/13.
- **Root cause:** the Windows WebP/WIC path flattened the sprite sheet alpha
  channel during crop/decode.
- **Fix:** derive and package a lossless four-channel RGBA PNG sheet and load it
  through WPF's native PNG decoder.
- **Regression test:** shared-resource inventory test plus final clean-package
  screenshots 11–14.
- **Reviewer result:** found during coordinator visual review; fixed and
  visually rechecked in signed 0.2.0.1.
- **Residual risk:** low.

## Remaining defects and evidence gaps

### WIN-QA-001 — Medium — Exhaustive final-package visual/action matrix is incomplete

- **Reproduction:** compare the 59-state UI oracle with
  `screenshots/`; only clean onboarding, expanded overlay, Now, and Settings
  have final 0.2.0.1 captures. Route, Party, Loadout, Act, compact overlay, and
  tray were exercised before the sprite fix and remain in the diagnostic
  folder; nested build/gear/run/act variants were primarily validated by tests
  and source/action review.
- **Root cause:** the integrated manual pass found and repaired the sprite
  decoder late; the entire state matrix was not replayed after rebuilding.
- **Fix required:** interactively replay and capture all 59 oracle states from
  the signed final package at available window sizes/DPI, including both
  onboarding branches, run switching/rename/catch-up, all class prerequisite
  paths, gear conflicts/swaps, Act transition/finalization, startup toggle, and
  every OpenRouter error surface using deterministic stubs.
- **Regression test:** add a version-stamped final visual/action checklist and
  capture index; keep the current 370 automated tests green.
- **Reviewer result:** outstanding; implementation/action ledgers are complete,
  but final runtime visual sign-off is not.
- **Residual risk:** a state-specific layout or disconnected routed action may
  remain despite controller coverage. The pull request must remain draft until
  this matrix is signed off.

### WIN-ENV-001 — Informational — Public development certificate export remains in Temp

- **Reproduction:** test
  `C:\Users\jcarbs\AppData\Local\Temp\BG3HonorAssistant-5703A3EFC56DC6766612C50BB0B0FF4C03D2A8E4.cer`.
- **Root cause:** the execution policy blocked deleting a file outside the
  workspace.
- **Fix required:** delete that exact public `.cer` file when permitted.
- **Regression test:** confirm the file is absent and all four certificate
  stores still lack the thumbprint.
- **Reviewer result:** coordinator cleanup check only.
- **Residual risk:** negligible; it contains no private key, and all user and
  machine trust/private-key entries were removed.
