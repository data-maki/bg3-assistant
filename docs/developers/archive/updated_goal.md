# Goal: Refine Act 1 Route Eligibility, Roster Planning, Loadouts, and Chat

Continue the existing BG3 Honor Mode Assistant. This is a focused release refinement, not a rebuild. Preserve every verified system and make the smallest production-safe changes required to make Act 1 guidance narratively correct, faster to scan, useful for the full companion roster, complete for Open Hand Monk, and better grounded in the player's real run state.

Read these files before changing anything:

- `AGENTS.md` or the user-supplied repository instructions;
- `goal.md`;
- `BG3_ASSISTANT_DESIGN.md`;
- `COMPLETION_AUDIT.md`;
- `RELEASE_CHECKLIST.md`;
- `README.md`;
- `LABREPORT.md`;
- `MISTAKES.md`;
- `LEARNINGS.md`;
- `TOOLCALLING_FAILURES.md`.

## Primary outcome

Help an experienced Honor Mode player answer, within a few seconds:

1. What is the safest useful thing I can do next?
2. What story or evidence prerequisite blocks the thing I want to do?
3. Which four characters are active, what are their current jobs, and are they ready?
4. What should each active character equip now, in this act and at this level?
5. What single mistake or dialogue choice is most likely to damage this run?

The interface must reduce cognitive load. Default surfaces should show a compact route, the current action, the active four, and only immediately relevant build/loadout information. Full reasoning, alternatives, archived work, camp planning, sources, and advanced overrides stay behind intentional disclosure.

## Verified baseline to preserve

Do not rebuild or regress:

- the signed Apple-silicon macOS app and embedded FastAPI backend;
- BG3 detection and launch, Screen Recording status, cross-Space capture, the optional shared 30-second capture loop, and clean vanilla operation without a mod;
- the Twilight Cleric pet, its hover-owned animation, middle-right default, persisted user position, compact peek, planner, map, and contextual chat;
- manual Done/Skip/Revisit progression, player-owned focus, archive, immediate advancement after player-confirmed completion, local persistence, and guide-version pinning;
- all 59 reviewed Act 1 walkthrough steps, all 19 fight checkpoints, regional phase routing, key dialogues, optional challenges, rewards, and Act 2 gate;
- nine reviewed builds, 102 level rows, existing loadout tracking, item effects/icons, and Act 1 map markers;
- the localhost Act 1 map, active pursuit planning, custom-marker export workflow, optional screenshot analysis, and optional telemetry fallback architecture;
- the existing backend, native, web, package, and signing checks.

Do not reintroduce retired product concepts. Do not expand walkthrough content into Acts 2 or 3 in this goal.

## Why a narrow patch is insufficient

### Simple patch — faster, but fragile and rejected

```text
ordered walkthrough JSON
        |
reorder the Kagha rows
        |
same four party slots ----> append more text to chat
```

This would fix one visible sequence but preserve the causes: skipped hard prerequisites count as satisfied, blocked steps can become recommendations, selected checkpoints bypass story eligibility, inactive companions have nowhere to live, and chat still lacks a coherent run snapshot.

### Chosen approach — smallest durable model

```text
guide facts + typed prerequisites + player outcomes
                      |
               eligibility engine
                 /           \
     automatic recommendation   player focus + named blocker
                 \           /
                  compact route rail

full roster + status + reviewed build + owned gear
                      |
              active-party projection (max 4)
                 /          |          \
           readiness     loadout     chat context
```

This keeps the current architecture, but separates concepts that must not be conflated: route order versus eligibility, recommendation versus player focus, full roster versus active party, and guide facts versus run state.

## Product principles

- One primary action per surface.
- List first; detail on demand.
- Never repeat a large challenge card for every route step.
- Recommendation and player focus are separate. The player can focus anything; the assistant must still show whether it is eligible.
- A skipped step is not automatically equivalent to a completed hard prerequisite.
- Readiness is calculated from active characters only.
- Inactive characters retain their levels, builds, roles, and equipment plans.
- Assigning a reviewed build means the player accepts its reviewed setup through the selected level; do not ask them to re-approve future multiclass choices.
- Show only the current level's build action by default. Do not show the next level unless the player asks for the full plan.
- Every empty equipment slot must be either filled, intentionally empty, unavailable in Act 1, or explicitly deferred with a reason.
- Only player action changes completion, companion status, story outcomes, or equipment ownership.
- Preserve the visible authority labels: `Guide fact`, `Assistant suggestion`, and `Unknown`.

## Priority 1 — Make route eligibility narratively correct

Audit all 59 steps, not only Kagha. Encode the prerequisites that make a step possible or safe, including evidence, dialogue outcomes, time-sensitive events, hostile/friendly branches, pickups, and regional travel gates.

### Required Kagha chain

Keep the early Arabella/Kagha chamber interaction distinct from the later Shadow Druid confrontation. The assistant must understand this sequence:

```text
Meet Kagha / save Arabella
          |
discover the Investigate Kagha lead
          |
reach the Sunlit Wetlands evidence route
          |
defeat or safely resolve the mud mephit + wood woad sanctuary challenge
          |
collect the Shadow Druid evidence
          |
return to expose/confront Kagha
          |
resolve the ritual and only then handle idol-dependent choices
```

Use the reviewed guide data to name the exact lead/evidence step. Do not merge `Save Arabella` with `Expose Kagha` in titles, summaries, chat, or route logic.

### Dependency model

Add typed dependency semantics without discarding existing data:

- `completion_required`: only the prerequisite's confirmed completion or required outcome satisfies it;
- `resolution_required`: confirmed completion or an explicitly acknowledged skip may satisfy it;
- `outcome_required`: a named player-confirmed dialogue/story outcome is required;
- `warning_only`: the route may continue, but the UI must show the consequence.

The exact schema may differ if an equally small representation already fits the models. The behavior is mandatory.

Rules:

- A hard prerequisite cannot be satisfied merely because the player pressed Skip.
- If a hard prerequisite was skipped, show `Revisit <step>` or the reviewed alternate branch; do not silently recommend the dependent step.
- Remove the fallback that recommends an ineligible step when no eligible step exists.
- Do not let `selectedCheckpointId` or player focus redefine the automatic recommendation.
- A focused but ineligible step remains selectable and visible with one concise blocker, such as `BLOCKED · collect the swamp letter first`.
- If no step in the current phase is eligible, give the precise prerequisite or reviewed alternate branch instead of a generic level-up message.
- Preserve contiguous regional travel. Eligibility must not reintroduce surface/Underdark/Grymforge bouncing.
- Review irreversible timing around the grove, harpies, Waukeen's Rest, Nere, the crèche, and entry to Act 2.

### Route validation

Add deterministic validation/tests proving:

- every dependency references an existing step;
- the dependency graph has no cycle;
- required predecessors occur before dependents in the reviewed order unless explicitly documented as a branch;
- every dependent step reports why it is blocked;
- Kagha is never automatically recommended before the required swamp evidence is confirmed;
- skipping the mud mephit/wood woad evidence step does not unlock Expose Kagha;
- focusing Expose Kagha early shows its blocker while preserving the real recommendation;
- all existing 59 steps and 19 linked fight checkpoints remain present.

## Priority 2 — Replace large route cards with a compact pursuit rail

Apply the same navigation hierarchy to the native Route tab and the localhost map's walkthrough panel. Keep the pet compact and unchanged except where it needs to display a new blocker.

### Target layout

```text
ACT 1 ROUTE · WILDERNESS                         8 LEFT

  ✓  Save Arabella                         L2
  ◆  Get swamp evidence                    L4  HIGH      [◎]
     Sparkle Hands · unlocks Kagha confrontation
  ◇  Expose Kagha                          BLOCKED       [◎]
     Needs: swamp evidence
  ⚔  Owlbear outcome                       L4  OPTIONAL  [◎]

  ARCHIVE · 18                                      [>]
```

`[◎]` represents a compact focus/target affordance, not a text button.

### Interaction requirements

- Default unresolved rows should be approximately 44–56 points/pixels high.
- Show one type/status icon, title, minimum level or blocker, optional danger/importance, and at most one reward/unlock line.
- Use a single shared detail surface for the selected row. Do not expand every row into a self-contained card.
- Move Done, outcome choices, Skip, Revisit, map, sources, failure conditions, and full tradeoffs into that detail surface.
- Keep completed/skipped steps hidden in one collapsed Archive with a count.
- Collapse phase headers to a compact label and remaining count.
- Make the focus icon a clear 28–32 point target with a tooltip/accessibility label.
- Hovering or keyboard-focusing the row must highlight the whole row with the existing BG3 bronze/gold visual language. Focusing the step gives the icon a persistent filled state.
- Visually distinguish `Recommended`, `Your focus`, `Blocked`, `Under level`, and `Optional` without relying on color alone.
- Preserve keyboard navigation, VoiceOver labels, reduced-motion behavior, and usable pointer targets.
- At the existing expanded planner height, show at least seven unresolved rows before scrolling when the shared detail surface is closed.
- Do not add more persistent filters or explanatory paragraphs to the route.

## Priority 3 — Separate the full roster from the active party

Replace the assumption that the four party rows are the entire run roster.

### Target layout

```text
ACTIVE PARTY                                             4 / 4
  Tav          L4  Flamadin                 Frontline
  Lae'zel      L4  Open Hand Monk           Striker
  Shadowheart  L4  Light Cleric             Support
  Astarion     L4  Control Martial          Control

CAMP & UNAVAILABLE                                      3
  Gale         Camp       Bladesinger
  Wyll         Camp       Fire Sorlock
  Karlach      Dead       No active build    Infernal Robe path
```

### Roster behavior

- Persist one custom character plus all reviewed Act 1 origin companions as a roster, even when they are not active.
- Enforce at most four active members. Show `3 / 4` if someone dies or leaves until the player promotes another available member.
- Support explicit player-owned statuses: `active`, `camp`, `unrecruited`, `unavailable`, `dead`, and `departed`. Use fewer values only if the same distinctions and future migration remain possible.
- A dead, departed, unavailable, or unrecruited companion cannot occupy an active slot.
- Changing status must never erase level, build, role, equipment ownership, or notes.
- Vision and optional telemetry may suggest context but may never change roster status.
- Allow a reviewed build to be assigned to every roster member, including camp members.
- Derive the visible combat role from the build by default. Put any role override behind Advanced controls.
- Keep fast level selection for the active party. Inactive members retain individually editable levels without cluttering the default view.
- Readiness, lowest-party level, and encounter warnings use active members only.
- Equipment/map recommendations default to active builds only. Add one deliberate `Include camp plans` control rather than mixing every roster build into the pursuit queue.
- Promoting or benching a companion must preserve their loadout completion and immediately recompute readiness, route advice, equipment pursuits, and chat context.

### Consequential companion outcomes

Companion status is not enough to explain why an outcome happened. Add a small player-confirmed story/outcome ledger or equivalent durable flags.

At minimum, support the user's example without inference:

- `Karlach: dead`;
- `Karlach killed for Mizora/Wyll path` as a confirmed story outcome;
- `Infernal Robe obtained` as a separate equipment fact.

Do not assume the robe was obtained merely because Karlach is dead. Surface a concise consequence warning before changing a companion to dead/departed when current route or gear plans depend on them.

### Migration

- Migrate the existing four `party` rows into the full roster without losing IDs, names, levels, builds, prepared tags, or equipment ownership.
- Mark those four migrated rows active.
- Add missing origin companions as camp or unrecruited according to the smallest non-destructive default.
- Make the migration idempotent and backward compatible with existing native and web run-state payloads.
- Preserve a compatibility projection if old API clients still expect `party`.

## Priority 4 — Complete the Act 1 Open Hand Monk loadout

Make `MO-OH` a complete current-level Act 1 plan that can be assigned to Lae'zel.

### Data requirements

For the Open Hand Monk, review and provide:

- a usable early-Act-1 baseline;
- level-gated upgrades through the end of Act 1;
- head, clothing/armor, gloves, boots, amulet, two rings, melee/unarmed intent, ranged/stat-stick intent, and critical consumables;
- exact act, map/region, acquisition method, source, and marker/area anchor for every obtainable Act 1 recommendation;
- a safe alternative for unique items contested by another active build;
- an explicit intentional-empty or unavailable label where Act 1 has no appropriate item;
- a short `why now`, not endgame build exposition.

### Correctness requirements

- Assigning Open Hand Monk to Lae'zel must show the reviewed Monk class step and role, not her default Fighter class.
- Do not recommend armor, shields, or weapons the selected build cannot use at the current level.
- In particular, do not present Adamantine Splint Armour as current Act 1 gear before the reviewed Fighter/heavy-armour respec actually grants proficiency. Show it as a later, locked option if it remains in the plan.
- Keep unarmed attacks and Tavern Brawler assumptions explicit enough to avoid recommending weapon-only item effects as unarmed upgrades.
- Show only gear available in or before the selected act by default; future-act best-in-slot may appear only in a collapsed `Later` section.
- Prevent duplicate ownership of unique equipment across active members, and show the reviewed alternative instead of leaving a slot blank.
- Add tests that fail when a reviewed active build lacks Act 1 slot disposition, acquisition guidance, a source, or level/proficiency compatibility.

## Priority 5 — Give chat a deterministic run-context snapshot

Chat must understand the player's current route state instead of receiving only a checkpoint ID and four generic party rows.

### Context shown above chat

Keep the context visible but compact:

```text
[Act 1 · Wilderness] [Active L4 · 4/4] [Focus: Expose Kagha] [Blocked: swamp evidence]
```

- Chips are inspectable and editable; they are not a paragraph.
- Distinguish `Recommended` from `Your focus` when they differ.
- Let the user ask in the scope of `Current`, `Route`, `Party`, or `Loadout` without opening a setup form.
- If the app lacks a required fact, show `Unknown` and let the player correct it.

### Snapshot contents

Build one structured, deterministic context snapshot containing only useful state:

- guide version, selected act, map region, route phase, and latest local detection timestamp/confidence;
- automatic recommendation, player-focused step, story/level blockers, and prerequisite chain;
- recent confirmed Done/Skip/Revisit states and player-confirmed dialogue/story outcomes relevant to the question;
- active four with level, reviewed build, derived role, current-level build action, and relevant equipped/missing items;
- inactive roster status when relevant, especially dead/departed companions and confirmed consequential outcomes;
- current checkpoint guide facts: minimum level, danger, enemies, legendary action, preparation, failure conditions, decision tradeoffs, reward, and irreversible warnings;
- optional screenshot evidence as bounded, timestamped evidence rather than route authority;
- authority metadata for every fact class.

The client may send this snapshot, but the backend must reload guide facts from trusted IDs rather than accepting duplicated free-form route prose as truth.

### Answer behavior

- Lead with one concrete answer or next action.
- Follow with the single highest-risk mistake.
- Mention only the party member, item, prerequisite, or dialogue choice relevant to the question.
- Put sources, longer alternatives, and background behind disclosure.
- Never imply an inactive/dead companion contributes to readiness.
- Never invent equipment ownership, companion status, completion, or story outcomes.
- Never auto-complete a step based on chat, vision, or telemetry.
- When focus is blocked, explain both the requested path and the current safe recommendation.
- Preserve deterministic offline guide answers when the model/API is unavailable.

Add contract tests covering:

- focused Kagha chat before evidence;
- an active Lae'zel Open Hand Monk;
- Karlach dead while Wyll or another companion is active;
- a camp member with a saved build that must not affect readiness;
- conflicting unique equipment;
- no screenshot and unknown story state;
- guide fact versus assistant suggestion versus unknown labeling.

## Implementation order

1. Add a `(current)` LABREPORT hypothesis for the route audit.
2. Audit all 59 dependencies and implement the typed eligibility behavior plus graph validation tests.
3. Add the additive full-roster/status/outcome model and migration; preserve the active-party compatibility view.
4. Complete and validate the Open Hand Monk Act 1 loadout and map anchors.
5. Replace native and web route cards with the compact rail and one shared detail surface.
6. Add the deterministic chat-context snapshot, context chips, and grounded answer behavior.
7. Run mutating UI QA only against an isolated run-state directory; never alter the player's current run during tests.
8. Rebuild/repackage, restart the actual app, prove backend ownership/content freshness, and verify the changed experience visually.
9. Update `LABREPORT.md`, `COMPLETION_AUDIT.md`, `README.md`, and `RELEASE_CHECKLIST.md` with actual evidence and limitations.

## Acceptance criteria

The goal is complete only when all of the following are proved:

### Route and UI

- Expose/Confront Kagha is never automatically recommended before the player confirms the required swamp evidence.
- Skipping the mud mephit/wood woad evidence step shows an alternate-path blocker rather than unlocking Kagha.
- The early Save Arabella interaction and later Expose Kagha confrontation are unambiguous everywhere.
- All 59 steps pass reference, cycle, ordering, and blocker-message validation.
- Player focus can point to any unresolved step without corrupting the automatic recommendation.
- Native and web route views use compact rows, a clear hover/focus affordance, a single detail surface, and one collapsed Archive.
- At least seven unresolved rows fit in the existing expanded planner when details are closed.
- Every route state provides a concrete action or precise blocker.

### Roster and readiness

- The run persists one custom character and the full Act 1 origin-companion roster.
- Exactly zero to four eligible roster members may be active; a fifth cannot be added.
- Every roster member can retain a level, reviewed build, derived/overridden role, status, and equipment plan while inactive.
- Dead/departed/unavailable members cannot affect active readiness.
- Lae'zel can be assigned Open Hand Monk and immediately appears with the correct current-level Monk action and role.
- Karlach can be marked dead without losing her state; the Infernal Robe outcome and item ownership remain separately player-confirmed.
- Existing four-member runs migrate without data loss in native and web persistence.

### Loadout

- Open Hand Monk has a reviewed, source-attributed, current-level-compatible disposition for every Act 1 equipment slot.
- Every recommended Act 1 Monk item has an acquisition location and usable map/area handoff.
- Unusable pre-respec Adamantine Splint is not shown as currently equipable.
- Unique-item conflicts produce a visible alternative.
- Equipment pursuits default to active members and include camp plans only when explicitly requested.

### Chat

- Chat visibly states its act/region, active party, focused or recommended challenge, and primary blocker.
- Chat correctly understands active versus camp/dead companions, current build steps, relevant equipment ownership, route prerequisites, and confirmed story outcomes.
- A Kagha question before swamp evidence names the evidence blocker and the safe current step.
- Responses lead with a concrete action and one primary risk while keeping sources/background secondary.
- Guide facts, assistant suggestions, and unknown information remain distinguishable.
- Chat, vision, and telemetry cannot change progress, roster status, equipment ownership, or story outcomes.

### Regression and release evidence

- Backend tests, native model checks, web checks, Swift release build, package extraction, embedded-backend smoke tests, and strict signature checks pass.
- Fresh visual QA covers hover, keyboard focus, route selection, roster promotion/bench/death, Lae'zel Monk loadout, chat context, and persistence across restart.
- The packaged app is restarted and shown to be serving the new route/roster/context schema rather than a stale backend.
- The existing pet, map, capture, vanilla fallback, archive, incident protocols, and manual progress behavior remain intact.

## Constraints and non-goals

- No game-memory reading.
- No required mod or telemetry dependency.
- No save manipulation.
- No combat, keyboard, or mouse automation.
- No automatic route completion or companion-status inference.
- No continuous cloud vision.
- No Act 2 or Act 3 walkthrough expansion.
- No MapGenie cloning or impersonation.
- No framework rewrite, new design system, or unrelated cleanup.
- Screenshots remain in memory unless debug capture is explicitly enabled.

## Execution protocol

- Inspect before changing and preserve user-authored dirty-worktree changes.
- Prefer additive migrations and the smallest release-safe diff.
- Before every significant experiment, add a `(current)` hypothesis to repo-local `LABREPORT.md`; update that same entry with the result and reflection when resolved.
- Record mistakes, failed tool calls, environment learnings, and missing capabilities in the repo-local meta files required by the user-supplied `AGENTS.md` instructions.
- Use an isolated run store for any mutating browser or app QA.
- Do not stop at scaffolding. Continue until the requested Act 1 flow is implemented, visually verified in the packaged app, and documented with fresh evidence.
