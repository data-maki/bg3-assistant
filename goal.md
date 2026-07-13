# Goal: Ship the BG3 Honor Mode Assistant for Act 1

Finish, verify, and release-harden the existing native macOS BG3 Honor Mode Assistant. Do not rebuild completed systems or expand into Act 2. Treat the current implementation, `BG3_ASSISTANT_DESIGN.md`, `COMPLETION_AUDIT.md`, and `RELEASE_CHECKLIST.md` as the baseline.

## Primary outcome

Deliver a production-functional Act 1 companion that helps an experienced Honor Mode player answer three questions immediately:

1. What should I do next?
2. Am I ready?
3. What single mistake is most likely to end the run?

The assistant must keep the party on a coherent, level-appropriate route, surface irreversible decisions before they happen, and prevent advancing to Act 2 without an explicit readiness review.

## Interaction contract

The Twilight Cleric pet at `/Users/jcarbs/.codex/pets/twilight-cleric` is the primary interface and should behave like a Codex pet: ambient, draggable, low-obstruction, and useful in a few seconds.

The collapsed pet should show only:

- current activity, minimum level, and danger;
- the next checkpoint;
- one short `AVOID` instruction;
- `Details`, `Ask`, and `Done` shortcuts.

Do not turn the pet into a dashboard. Assume the player already knows BG3 mechanics.

The expanded planner should use progressive disclosure:

- default: `DO NOW`, readiness gate, `DON'T DIE`, key Honor choices, and `PREP`;
- on demand: enemies, legendary actions, all failure conditions, irreversible events, quests/pickups, completion checks, skip/revisit controls, guide sources, build background, map calibration, and optional screenshot analysis.

## Verified baseline to preserve

The repository already contains and has verified:

- a signed Apple-silicon macOS app with an embedded frozen FastAPI backend;
- BG3 process detection, Steam launch, Screen Recording preflight, cross-Space ScreenCaptureKit capture, and automatic two-second local analysis;
- the validated Twilight Cleric pet, compact overlay, planner, contextual chat, and manual Done/Skip/Revisit flow;
- deterministic level-aware regional routing with explicit player-owned progress;
- all 19 reviewed Act 1 checkpoints, eight source-attributed builds, 90 level rows, and 56 map markers;
- local run persistence, guide-version pinning, readiness checks, Act 2 blockers, and build-aware party guidance;
- a localhost Act 1 map with fight/item/build filters and MapGenie attribution/handoff;
- real Wilderness image registration with 132 inliers at confidence 1.0 on a corrected 2560×1440 BG3 frame;
- 32 backend tests, native model/detector/map/persistence/overlay-geometry checks, Swift release builds, and strict signature verification of the app and extracted ZIP.

Do not regress these behaviors or reintroduce concepts from the retired prototype.

## Guidance authority

Use this spreadsheet as the source of truth for Act 1 fight facts, preparation, minimum recommended levels, notes, and region-aware coordinates:

<https://docs.google.com/spreadsheets/d/1XLF6fH9D4uqmDfSoNzkTs1TuHxGn0K-4EJ82BVUQJqk/edit?gid=0#gid=0>

Preserve three explicit authority levels:

- **Guide fact:** directly supported by the reviewed guide data.
- **Assistant suggestion:** derived from guide facts, route state, party state, or optional screenshot evidence.
- **Unknown:** not established by the reviewed data.

Vision and chat may explain context but must never invent route facts or automatically complete progress. Only the player can confirm completion.

## Remaining goal work

### 1. Close live map-overlay acceptance

- Run the packaged app against a loaded BG3 Wilderness map.
- Confirm the automatic two-second loop reports local alignment.
- Visually confirm current/upcoming click-through markers are correctly placed.
- Pan once, zoom once, and resize or change window geometry once.
- Confirm markers recompute and remain aligned without an LLM call.
- Record concrete evidence in `LABREPORT.md` and `COMPLETION_AUDIT.md`.

### 2. Release hardening

- Keep the app self-contained: users must not need the repository, Python, `uv`, or Swift.
- Verify first-run Screen Recording messaging, automatic capture, BG3 launch/detection, pet dragging, planner actions, persistence, localhost map, and clean backend shutdown.
- Run the complete backend/native/build/package suite.
- Verify the final ZIP after extraction and publish its SHA-256 in `RELEASE_CHECKLIST.md`.
- Use a permanent reverse-DNS bundle ID, Developer ID Application certificate, notarization, stapling, and Gatekeeper assessment when the publisher inputs are available.
- If signing/notarization inputs are unavailable, do not fabricate or weaken the release gate. Finish all internal work and report the exact missing publisher-owned inputs.

### 3. Final usability pass

- Prefer fewer, higher-value words over comprehensive default screens.
- Remove repeated explanations and mechanics an experienced BG3 player already knows.
- Keep safety-critical information visible; move reference depth behind intentional disclosure.
- Every state must provide a concrete next action or a specific blocker.
- Preserve fast party-level selection and show only the current and next build steps by default.
- Model setup as one custom character plus three selectable Act 1 story companions, with level and reviewed-build controls visible for every slot.
- Default the collapsed pet to the vertical middle of the game's right edge; migrate obsolete saved defaults without overriding later user drags.

## Map and privacy constraints

- Screenshots remain in memory unless debug capture is explicitly enabled.
- Do not send the two-second screenshot loop to an LLM.
- Use local artwork registration for Wilderness pan/zoom/resize alignment.
- Prefer explicit, user-triggered BG3 custom-marker synchronization over a permanent projected map overlay: export only the current act/level/build queue, activate a temporary alignment overlay, let an external Computer Use session place named markers, verify with screenshots, and persist a manually confirmed sync fingerprint.
- Keep the native app Screen Recording-only. Computer Use has separate control authority and must never treat Screen Recording as input authority.
- Use explicit region bounds plus saved calibration only as the documented fallback for non-Wilderness maps.
- Do not clone or impersonate MapGenie; use attribution, public tiles where permitted, local reviewed markers, and a direct handoff to the source.

## Explicit non-goals

Do not add:

- game-memory reading;
- mods or save manipulation;
- combat automation;
- native keyboard or mouse control; the only allowed exception is an explicit external Computer Use session that creates named custom markers on the open BG3 map;
- automatic route completion;
- continuous cloud vision;
- Act 2 or Act 3 content;
- speculative framework rewrites or unrelated cleanup.

## Acceptance criteria

The goal is complete only when:

- the pet remains unobtrusive and decision-first;
- the assistant always gives a next action or a precise blocker;
- all 19 checkpoints persist per run and can be completed, skipped, or revisited manually;
- party level/build state changes readiness and route guidance;
- under-level, missing preparation, legendary actions, failure conditions, key dialogue choices, and irreversible events appear at the right moment;
- Act 2 readiness blocks unresolved important work;
- guide facts, suggestions, and unknowns remain distinguishable;
- BG3 capture permission is reported accurately and automatic capture works across Spaces;
- real packaged Wilderness markers remain aligned through pan, zoom, and geometry change;
- the player can preview/export the relevant marker queue and explicitly sync named fight/equipment markers into BG3 without duplicate automatic reruns;
- the embedded backend, app, localhost map, persistence, and shutdown work without the source checkout;
- backend tests, native checks, Swift release build, code signing, ZIP extraction, and documentation verification pass;
- public signing/notarization passes, or the only remaining blocker is explicitly documented publisher-owned credentials;
- `README.md`, `COMPLETION_AUDIT.md`, and `RELEASE_CHECKLIST.md` match the actual release artifact.

## Execution protocol

- Work from current evidence; inspect before changing.
- Prefer the smallest release-safe diff.
- Before every significant experiment, add a `(current)` hypothesis to repo-local `LABREPORT.md`.
- Update that same entry with result and reflection once proved, invalidated, blocked, or discarded.
- Record mistakes, tool failures, environment learnings, and missing capabilities in the repo-local meta files required by `AGENTS.md`.
- Continue until the Act 1 product is verified end to end, not merely scaffolded.
