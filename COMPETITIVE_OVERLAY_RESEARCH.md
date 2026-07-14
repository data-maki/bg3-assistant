# Competitive overlay research for BG3 Honor Mode Assistant

## Executive conclusion

The strongest competitive overlays do not win by keeping more information on screen. They win by doing one of four jobs at the moment it matters:

1. **Offload memory** — track known cards, cooldowns, builds, or objectives.
2. **Compress preparation** — turn a large dataset into the few choices relevant to the next phase.
3. **Reduce uncertainty** — show risk, matchup, or readiness in a form the player can scan immediately.
4. **Close the learning loop** — explain what happened after the decision, not while the player is overloaded.

For BG3 Honor Mode, the best product direction is a phase-aware pet that changes its compact briefing across exploration, preflight, dialogue, combat, and recovery. The planner remains the reference surface, but it should not be the normal way to consume guidance.

## What successful overlays provide

| Game and product | Important features | Player value | Best BG3 transfer |
|---|---|---|---|
| Hearthstone Deck Tracker / HSReplay | Deck, hand, secret, replay, and match-history tracking; Battlegrounds combat simulation and lethal odds | Removes working-memory burden and makes uncertainty legible without requiring an alt-tab | Maintain a player-confirmed run ledger; compress readiness into a risk band and one blocker; never invent an exact win probability from incomplete state |
| Valorant Tracker | Map/mode-aware agent preparation, current-match context, lineups, personal trends, and post-match breakdowns | Puts the right reference inside a short preparation window and connects it to later learning | Show exact Honor dialogue/preflight guidance only when that activity is current; give one-click access to location-specific preparation |
| Dota Plus | Multiple hero/item choices, recommendations that recalculate after build deviations, level-specific ability suggestions, death summaries, and post-game benchmarks | Treats recommendations as adaptive options rather than a brittle script; explains failure after attention pressure has passed | Recalculate route/readiness after party, level, or equipment changes; offer safe/fast/defer choices; add a post-fight stabilization summary |
| Blitz / Porofessor / Mobalytics for League | Pre-game setup, builds and power spikes, timers/state summaries, hotkey access, movable/hidden widgets, and post-match evaluation | Removes setup friction, prevents research during play, and supports intentional disclosure | Hold-to-peek shortcut; minimal/focus/reference presets; current-level action only; session recap rather than a permanent dashboard |

## Important product lessons

### 1. The overlay should be phase-specific

Competitive overlays change what they show between draft, match, and post-match. Our current collapsed pet uses one general layout for every activity. The content changes, but the interaction contract does not fully acknowledge the player's phase.

The target model:

```text
walkthrough + party + manual confirmation + local screen classification
                              |
                              v
                   relevance / phase engine
                              |
        +-----------+---------+----------+-----------+
        |           |                    |           |
     EXPLORE     PREFLIGHT            COMBAT      RECOVER
        |           |                    |           |
   next place   first blocker       pinned risk   reset party
   why now      ready / not ready   one fallback  confirm outcome
```

Vision may suggest the phase, but only the player changes progress or confirms an outcome.

### 2. Recommendations should adapt, not dictate

Dota Plus presents several item sequences and recalculates when the player deviates. Riot's general product policy expresses the healthier principle directly: highlight important decisions and give multiple choices rather than removing decisions.

For a BG3 checkpoint, show three route choices only when they materially differ:

- **Recommended now** — safest useful activity at the current level and region.
- **Lower risk** — an optional nearby XP/pickup step.
- **Defer** — why the encounter should be left until a later level.

The player should never feel that changing a companion, build, or item has invalidated the assistant. Recompute from actual saved party state and explain the one changed blocker.

### 3. Readiness should be a compressed verdict

Hearthstone's combat odds and League's power-spike notices work because they turn many facts into a glanceable state. BG3 cannot honestly calculate exact win odds without reading the full game state, so the overlay should use deterministic readiness states:

```text
READY       minimum level met; no reviewed blocker
CAUTION     viable, but one important preparation gap
BLOCKED     below guide level or missing a required route prerequisite
UNKNOWN     equipment/resources not confirmed; no false certainty
```

Collapsed view shows only the state and highest-impact reason. The planner owns the full checklist.

### 4. Hotkey access is more valuable than another persistent widget

DotaPlus uses a toggle hotkey; Mobalytics layers information behind scoreboard-key combinations; Overwolf explicitly recommends hotkeys, non-obstruction, and context-relevant information. BG3 should add configurable shortcuts for:

- **Hold to peek** — show the compact card only while held.
- **Toggle planner** — open/close without finding the pet.
- **Panic** — reveal only escape feasibility and the current fight's fallback.
- **Confirm done** — open confirmation; never complete immediately from the keypress.

The pet remains the discoverable interface. Hotkeys make it disappear from the experienced player's attention until needed.

### 5. Recovery deserves its own moment

Dota Plus's death summary moves analysis to a moment when the player can use it. Honor Mode needs the analogous **Stabilize** state after a dangerous fight:

- protected NPC / completion condition;
- downed or dead party members to resolve;
- concentration, summons, and short/long-rest resources to reset;
- loot or dialogue that becomes unavailable after leaving;
- whether travel or resting is currently safe.

This should be three lines at most, then return to exploration after the player confirms the outcome.

### 6. Personalization should control density, not the truth

League overlays let users move, hide, scale, and change widgets; Blitz even exposes a tilt-free mode. The equivalent BG3 presets should be:

- **Minimal** — pet plus danger state; hover or hotkey for text.
- **Focus** — current objective, readiness, one `AVOID`, actions. Recommended default.
- **Reference** — pinned combat or dialogue card until dismissed.

The player can change scale, surface strength, shortcut keys, and warning sound. Safety-critical facts, source labels, and readiness logic remain consistent across presets.

## Proposed overlay

### Current general-purpose collapsed card

```text
┌──────────────────────────────────┐
│ pet  NEXT · Secluded Cove        │
│      L4+ · HIGH                  │
│ AVOID · Do not let Mirkon die    │
│ [Plan] [Talk] [Ask] [Done]       │
└──────────────────────────────────┘
```

### Target phase-aware collapsed card

```text
EXPLORE                           PREFLIGHT
┌────────────────────────────┐    ┌────────────────────────────┐
│ pet  NEXT · Secluded Cove  │    │ pet  CAUTION · 2/3 READY  │
│      WHY · closest L4 goal │    │      Missing: Calm Emotion│
│ [Plan] [Map] [Done]        │    │ [Fix] [Ready] [Details]    │
└────────────────────────────┘    └────────────────────────────┘

DIALOGUE                          COMBAT / RECOVER
┌────────────────────────────┐    ┌────────────────────────────┐
│ pet  SAY · Defend the child│    │ pet  DON'T DIE · Luring Song│
│      AVOID · Attack Kagha  │    │      PANIC · break control │
│ [Tradeoffs] [Record]       │    │ [Panic] [Stabilize]        │
└────────────────────────────┘    └────────────────────────────┘
```

The actual pet actions may remain `Plan`, `Talk`, `Ask`, and `Done` for muscle memory. The contextual verbs above describe the information hierarchy and the primary button inside each action, not a requirement to constantly rearrange the shortcut row.

## Recommended implementation order

### P0 — highest value

1. **Phase state machine:** `explore`, `preflight`, `dialogue`, `combat`, `recover`, `levelUp`; manual state transitions with optional vision suggestions.
2. **Compressed readiness strip:** status, `x/y` confirmed preparation, first blocker, and source/assumption indicator.
3. **Combat pin refinement:** only legendary trigger, protected target, and one fallback; no route or build prose.
4. **Post-fight Stabilize card:** completion condition, irreversible pickup/dialogue, resource reset, then player confirmation.
5. **Hold-to-peek and toggle hotkeys:** no gameplay input, no immediate completion.

### P1 — strong differentiation

6. **Adaptive choice stack:** Recommended now / Lower risk / Defer, constrained to the current region to prevent route bouncing.
7. **Session resume/recap:** last completed activity, decisions recorded, unresolved irreversible items, and exact first action next session.
8. **Density presets:** Minimal / Focus / Reference plus scale and surface strength; preserve the user's dragged anchor.
9. **One-tap handoff:** current location opens the filtered local map; current equipment blocker opens its member/item card.

### P2 — validate before building

10. **Near-miss review:** player can record “almost wiped” and select the cause; aggregate privately to improve warnings.
11. **Local screenshot classification:** suggest dialogue/map/combat phase, never progress or tactical actions.
12. **Optional audio:** one short lethal warning category with cooldown and explicit opt-in.

## What not to copy

- A full player/opponent-stat dashboard. BG3 has no useful equivalent and it creates visual noise.
- Exact win probabilities. Our known state is insufficient, so a number would create false confidence.
- Continuous “do this now” combat coaching. It becomes stale, removes decisions, and conflicts with the product's experienced-player premise.
- Automatic build import, inventory control, or route completion.
- Advertising, engagement streaks, or achievement layers inside the gameplay overlay.
- Unbounded notifications. Only newly relevant, safety-critical changes should interrupt.

## Success measures

- Player can answer **next / ready / biggest danger** from the collapsed state in under two seconds.
- Normal collapsed surface stays below roughly 8% of a 16:9 game window and avoids the minimap/hotbar safe bands.
- At most one proactive warning per checkpoint unless readiness meaningfully changes.
- Preflight-to-ready requires no more than two overlay interactions after party setup.
- Every session begins with a concrete next action; no generic home/dashboard state.
- False urgent-warning rate and accidental completion rate remain effectively zero.
- Reference depth is opened intentionally rather than rendered by default.

## Sources reviewed

- [HSReplay Hearthstone Deck Tracker](https://hsreplay.net/downloads/)
- [HSReplay Battlegrounds overlay](https://hsreplay.net/battlegrounds/overlay/)
- [Valorant Tracker](https://tracker.gg/valorant/app)
- [Riot Valorant developer policy](https://developer.riotgames.com/docs/valorant)
- [Valve Dota Plus](https://www.dota2.com/plus/)
- [Overwolf DotaPlus](https://www.overwolf.com/app/overwolf-dotaplus)
- [Blitz for League](https://blitz.gg/welcome/lol)
- [Porofessor](https://porofessor.gg/en/download)
- [Mobalytics League overlay](https://mobalytics.gg/lol-overlay/)
- [Riot League developer policy](https://developer.riotgames.com/docs/lol)
- [Overwolf overlay behavior guidelines](https://dev.overwolf.com/ow-native/guides/product-guidelines/app-screen-behavior/in-game-overlays/)
