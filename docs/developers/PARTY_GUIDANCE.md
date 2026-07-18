# Party Guidance Architecture

**Status:** Approved for implementation

## Product Goal

Party answers the recurring question: "What does each active character do at
this level?" Roster administration and build configuration are secondary
destinations. Ability guidance must tell a player exactly what to enter in
BG3, not collapse character creation, level progression, equipment, permanent
boons, and consumables into one unexplained score.

## Information Architecture

The native Party surface uses four layers backed by the shared Party data:

1. **Guidance board:** one glance row for each active member. It shows the
   exact current build step, its choices, one-line tactics, and whether an
   ability setup is due. Future-level detail stays off this screen.
2. **Member detail:** level, build, full current guidance, and the active
   point-buy/bonus/final-value table inline. Destructive planner reset is
   explicitly named and confirmed.
3. **Ability progression:** an optional expansion from member detail explains
   alternate respec setups and every later ASI, feat, permanent boon,
   equipment setter, and consumable.
4. **Manage party members:** one compact row per known member with placement
   controls for Active, Camp, or Unrecruited. Moving into a full active party
   asks which active member to replace.

No landing-page value is called "actual" unless it was recorded by the player.
No final target is presented without its source assumptions.

## Ability Contract

Each reviewed build carries explicit setup events and progression sources.

### Setup Event

- Stable ID.
- Character level at which the setup is performed.
- Human label and reason.
- Six point-buy scores before bonuses.
- The distinct abilities receiving +2 and +1.
- Six resulting values shown in BG3.
- First class and class order after the setup.

The backend validates the BG3 rules: every point-buy value is 8-15, the budget
is exactly 27, bonus abilities differ, and final values equal point buy plus
the selected bonuses.

### Progression Source

- Stable ID and display label.
- Ability, source kind, and application mode.
- Additive value or minimum/setter value.
- Level range when applicable.
- Optional item key for Loadout ownership.
- Whether the source is unique across the party.
- A short explanation of the assumption.

Source kinds are ASI, feat, permanent, equipment, and consumable. ASIs and
feats are recommendations derived from the reviewed plan. Equipment is active
only when the item is assigned in Loadout. Permanent and consumable sources
are explicitly recorded by the player. Unique rewards cannot be assigned to
multiple members, and one character cannot have multiple active elixirs.

## Player-Owned State

A party member stores the setup event last confirmed in BG3, recorded external
ability sources, and whether its scores came from the selected build. Browser
and native schemas must round-trip all member fields. Partial web updates merge
with the existing member snapshot instead of deleting fields unknown to an
older client.

## Interaction Rules

- Selecting a different build applies its recommended creation values only
  after any destructive consequences are confirmed.
- Importing a build from a member editor assigns it to that member.
- "Respec" describes an upcoming BG3 recipe. "Reset character plan" is the
  destructive application action and always requires confirmation.
- Dead, Departed, Unavailable, Camp, and Not recruited remain distinct.
- Failed Party actions appear in Party, not only in Settings diagnostics.
- Four active members is a maximum, not a completion requirement.
- Current-step labels use the matched build-step level. Older fallback advice
  is explicitly labelled "Latest plan Lx."

## Presentation Rules

- 9pt is the minimum native type size.
- Text and symbols carry meaning independently of color.
- The ability recipe uses a text table, not a segmented score bar.
- Every score includes its gameplay modifier in the source ledger.
- Both surfaces preserve the same terminology and hierarchy even when their
  responsive layouts differ.
