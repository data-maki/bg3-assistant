# Mistakes

Durable corrective rules only. Full incident narratives purged 2026-07-13; each bullet is an invariant that already failed once in this repo.

## Product / data

- Every selectable build must pass a current-act interim-loadout coverage check. Later-act defining items supplement; they never replace “what to wear now.”
- Build review includes current-level proficiency validation and complete Act-scoped slot coverage.
- Slot-completeness checks must run at every supported level, including intentionally empty/stat-stick slots; a final-act list can look complete while the L1 bridge is still missing a disposition.
- Adding map objectives also expands the icon denominator. Add their local icon assets and registry entries in the same change instead of lowering the established visual-coverage test.
- Keep Party (current-level actions) separate from Equipment (act-scoped gear/location); preserve member ID/name/level/build in shared state.
- Canonical route checkpoint IDs are not item-acquisition phrases (`fight-nautiloid-zhalk` ≠ `fight-nautiloid-helm`).
- Model evidence, dialogue, encounter, and branch prerequisites explicitly; regional order + minimum level is not enough story validation.
- Keep a full persistent roster separate from the four-member active-party projection; story outcomes (dead/departed/unrecruited) are not inferred readiness.
- Equipment-selection tradeoffs are not dialogue; keep encounter labels honest (`PICKUP`/`EXPLORE` vs `TALK`).
- Verify acquisition NPC/location before curating rewards; build familiarity is not enough.
- Release counts and schema claims come from the packaged artifact (and source comparison), never from an intermediate implementation note.
- Do not overclaim live acceptance: synthetic positive alignment ≠ loaded-save map proof.
- Do not put item packages or known non-Honor builds in human-facing selectors.
- Plain-text spreadsheet cells must not start with `=`, `+`, `-`, or `@` unless they are formulas.
- Validate TSV/CSV shape before upload; missing columns shift advice into the wrong fields.
- When replacing a shorter Sheet tab, overwrite a padded range so stale rows below do not survive.

## Overlay / UX

- Do not teach experienced Honor players routine game hygiene (heal, rest, end initiative, clear ordinary hazards) or gate progression on confirming it. Surface only encounter-specific, non-obvious failure states and recovery actions triggered by an actual incident.
- Treat Party as a four-seat assignment flow, not four expanded build dossiers. Default rows should answer `who`, `level`, `build`, and `do now`; class detail, gear, and inactive-roster management require intentional expansion.
- Do not show the summary, decision prompt, option tradeoffs, incident protocol, and risk/reward analysis at once. Default fight/dialogue detail gets one action, one `AVOID`, and compact readiness; supporting depth belongs behind one disclosure.
- When a known installed app already handles the same macOS permission correctly, diff its public source and signed bundle before inventing or iterating a custom TCC flow. Passing local state-machine tests is not evidence that the OS registration lifecycle matches a working product.
- Permission QA must launch the stable installed `/Applications` copy. Repeatedly rebuilding and launching the repository bundle changes the path/inode under TCC and contradicts the first-run contract even when the signed requirement is stable.
- Middle-right is first-run/migration fallback only; persist an explicit user-position flag with the normalized anchor and regression-test across collapse/expand and relaunch.
- Persist placement only for real user movement (drag / frame differing from programmatic target)—not click-up during programmatic resize.
- Compact pet contract: Details/Ask/Done plus one concise `AVOID`; expose child accessibility labels; no flexible empty drag zone that steals height.
- Pet rests still; drive v2 look cells from hover/pointer; put route danger in the tooltip, not autonomous animation.
- Prefer intrinsic chrome height and one availability-gated Liquid Glass surface over nested opaque cards and large empty material.
- Never treat `SCShareableContent` enumeration as Screen Recording authorization. It can expose display/window metadata without pixel access, producing a false green state while the app has no TCC row. Include `NSScreenCaptureUsageDescription`; offer consent on first launch, invoke `CGRequestScreenCaptureAccess` directly from the user's Continue click, then verify actual pixels. Do not rely on an unexplained startup request to create the row.
- Party primary flow: act-wide input, current-level choice, act-relevant equipment/location; bury next-level exposition and Acts 2/3 until reviewed.
- Promote `Done` on the compact pet with the same safety confirmation as expanded; advance immediately after confirmation.
- Rank BG3 windows by visible area; capture at reported 1:1 size; match Larian identity, not substring `bg3`.

## Release / process

- Persistence QA must prove a real cross-process restart with multiple mutated fields. A successful in-process `save`/`load` roundtrip does not catch startup overwrites, split stores, or unstable application-support paths.
- Keep shared SwiftUI view helpers `@MainActor` when they call actor-isolated theme modifiers, even after removing their last stateful parameter.
- SwiftUI may invoke startup from more than one scene before the first async call returns. Set an actor-isolated startup latch before the first `await`; a process singleton does not prevent duplicate initialization inside one process.
- Before calling any game integration publishable/approved, verify publisher authoring tool, dependency model, supported APIs, platform curation, and submission path. Valid archive ≠ official eligibility.
- Quit through the normal app lifecycle for release smoke tests; prove new GUI PID owns the backend; do not treat `/health` alone as ownership.
- Process retirement uses service ownership or listener identity—never `pgrep -f` / arbitrary command-line substrings (they match the verification shell).
- Record release hashes from an isolated checksum command, not concatenated build/Gatekeeper output.
- Trace completion claims through the real native payload and persistence path; backend tests with synthetic context can overstate what the shipping client actually sends.
- SwiftUI toggle bindings must apply the requested Boolean idempotently. A setter that blindly flips state can confirm story outcomes when the control merely appears or is reconciled.
- Issue build, package, signature, and runtime checks as separate legible commands—not one `&&` chain that hides which step failed.
- Compound validations run fail-fast; expected failures live in an explicit subshell so a later expected non-zero cannot mask an earlier real failure.
- Mutating UI QA uses an isolated `runs_dir`; ports do not isolate the run ledger.
- For packaged Computer Use QA, never rely on `env VAR=... AppBinary`: targeting the bundle can relaunch it through LaunchServices without that environment. Set `BG3_ASSISTANT_STATE_DIR` with `launchctl setenv`, verify it in the GUI process, and unset it before returning to the player's app.
- Multi-statement Swift functions, getters, and view builders need explicit `return` after local declarations.
- Precompute optional/interpolated SwiftUI labels before the view builder; chained `map`/`??` expressions inside `Text` can exceed the compiler's type-check budget.
- Preserve zero-argument call sites with closures when parameterizing methods used as `Button(action:)` / menu references; search all direct method references.
- Prefer explicit closures for SwiftUI `Binding` setters—direct method references have crashed Swift 6.3.2 IRGen in this project.
- Visually inspect formula-driven sheets and run a changed-input scenario; a zero-error formula scan is not sufficient.
- Rewrite shipping goals when the evidence changes so agents do not rebuild verified systems.
- Open the `(current)` LAB experiment before implementation. The compact route-rail refactor once landed before its experiment entry; commentary is not a substitute for the repo-local protocol.
- Do not let a useful local detector become an always-on product default. Capture cost, permission prompts, and remote-analysis disclosure must follow an explicit feature toggle; inferred completion belongs in an evidence ledger until the player confirms it.
- Disabling a timer is insufficient if app-activation callbacks can still probe pixels. Every capture entry point—including permission-return reconciliation—must honor the feature-off gate unless it is completing an explicit pending permission request.
