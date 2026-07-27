# Signed-package UI/action matrix

These are real captures from the signed ARM64 MSIX integration sequence at the
available Windows 11 200% DPI. The sequence ended at 0.2.0.11. Affected states
were recaptured after each integrated fix; images do not contain embedded
package-version metadata.

## Coverage

| Oracle rows | Evidence |
|---|---|
| 01-14 | Fresh onboarding, Focus overlay, companion-only overlay |
| 16-20 | Route filters, step detail, skip confirmation, exact revisit |
| 21-22 | Now and expanded context |
| 23-29 | Party, member detail/reopen, reviewed/manual build, Bard prerequisites, roster |
| 30-36 | Empty/built loadout, import, assignment, gear detail, target, equip |
| 37-39 | Act ledger and Act 2/3 views |
| 40-48 | Empty chat, Settings/diagnostics, all overlay densities, typed-only policy |
| 51-60 | Mid-run onboarding/catch-up, second run, ability recipe, reset confirmation |

There are 57 PNGs for 57 captured oracle rows. Oracle row 15 does not exist.
Rows 49 and 50 are intentionally not represented by screenshots:

- 49 requires an in-flight provider request.
- 50 requires a successful provider response.

The user did not opt into the bounded live canary, so the existing credential
was never read and no network request was sent. Deterministic tests exercise
the client success/cancellation/error mappings and structured answer/source
decode. Source/action review covers the WPF waiting, answer, source-link, and
control-enable transitions. Neither screenshot is claimed as runtime evidence.

## Action audit

The packaged pass exercised:

- fresh and Act 1/2/3 mid-run onboarding, including landmark catch-up;
- Focus, Minimal, and Reference overlay states;
- tray collapse, same-PID restore, menu commands, and Quit;
- run creation, switching, rename, catch-up, and upgrade persistence;
- Route filtering, consequential skip confirmation, and exact archived-step
  revisit;
- roster status, active capacity, level, reviewed assignment, manual build,
  Bard choices, undo, ability recipe, and reset confirmation;
- empty and populated loadouts, item detail, target, and equipped state;
- Act 1 ledger plus Act 2/3 previews and transition/finalization surfaces;
- Settings key-status-only UI, density, spoiler policy, startup off -> on ->
  off, diagnostics, legal disclosures, and tour replay controls.

Automated coverage supplies the full all-12-class catalog/prerequisite matrix,
gear conflict/swap rules, every Act gate/finalization branch, SQLite recovery
and revision cases, all OpenRouter failure mappings, and package-boundary
invalidation cases. See the five TRX files in `../../results/`.
