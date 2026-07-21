# Party Guidance Architecture

**Status:** Implemented in the native Swift runtime

## Product Goal

Party answers the recurring question: "What does each active character do at this level?" Roster administration and build configuration are secondary destinations. Ability guidance must tell a player exactly what to enter in BG3, not collapse character creation, level progression, equipment, permanent boons, and consumables into one unexplained score.

## Information Architecture

The native Party surface uses four layers backed by the same `HonorRun` and build data:

1. **Guidance board:** one glance row for each active member. It shows the exact current build step, its choices, one-line tactics, and whether an ability setup is due. Future-level detail stays off this screen.
2. **Member detail:** level, build, full current guidance, and the active point-buy/bonus/final-value table inline. Destructive planner reset is explicitly named and confirmed.
3. **Ability progression:** an optional expansion from member detail explains alternate respec setups and later ASI, feat, permanent boon, equipment setter, and consumable sources.
4. **Manage party members:** one compact row per known member with placement controls for Active, Camp, or Unrecruited. Moving into a full active party asks which active member to replace.

No landing-page value is called "actual" unless it was recorded by the player. No final target is presented without its source assumptions.

## Build Data Sources

Reviewed builds originate in `data`, pass through the Python guide/catalog loaders, and are compiled by `backend/scripts/export-swift-resources.py` into `mac/BG3Assistant/Resources/Data/guide-bundle.json`. The released app reads that JSON directly through `GuideRepository`; it does not request Party data from a local or hosted backend.

Imported builds are created by Swift from a public URL using the provider selected in Settings. They are saved separately to `~/Library/Application Support/BG3HonorAssistant/imported-builds.json` and merged into the native build picker. Imported builds remain labelled `Imported; verify choices in game` because structured extraction and point-buy validation do not prove complete build legality.

## Ability Contract

Each reviewed build can carry explicit setup events and progression sources.

### Setup Event

- Stable ID
- Character level at which the setup is performed
- Human label and reason
- `pointBuyScores`: six base scores before bonuses
- `bonusTwo`: the ability receiving +2
- `bonusOne`: a different ability receiving +1
- `finalScores`: the six resulting values shown in BG3
- First class and class order after the setup

For imported builds, the provider schema constrains each point-buy value to 8-15 and requires all six abilities plus explicit `bonusTwo` and `bonusOne`. Swift then deterministically verifies that the bonuses differ and `AbilityProgression.pointBuyCost(pointBuyScores)` is exactly 27. Swift computes `finalScores` itself by adding +2 and +1 to the named abilities; model-supplied final starting values are not authoritative.

Imported class progression is normalized separately. Character levels must be unique and in 1-12. If `finalSplit` does not total 12, Swift replaces it only when the extracted level rows yield exact per-class maxima totaling 12. A level-12 guide that still does not total 12 is rejected. These checks do not validate every class choice, spell, feat, or multiclass prerequisite.

### Progression Source

- Stable ID and display label
- Ability, source kind, and application mode
- Additive value or minimum/setter value
- Level and act range when applicable
- Optional item key for Loadout ownership
- Whether the source is unique across the party
- A short explanation of the assumption

Source kinds are ASI, feat, permanent, equipment, and consumable. ASIs and feats are recommendations from the reviewed plan. Equipment is active only when the player assigns the item in Loadout. Permanent and consumable sources are explicitly recorded by the player. Unique rewards cannot be assigned to multiple members, and one character cannot have multiple active elixirs.

## Player-Owned State

A party member stores its roster status, level, selected build, the setup event last confirmed in BG3, recorded external ability sources, and whether its scores came from the selected build. This state belongs to the full `HonorRun` snapshot in `state.sqlite3`; Swift is its runtime authority.

Run state and imported build storage are deliberately separate. A run references build IDs and records character-specific confirmations, while `imported-builds.json` makes reusable imported `BuildSummary` values available to all runs and characters on that installation. The selected AI provider is an app setting in SQLite. The OpenRouter key is never part of Party, run, or imported-build state; it exists only in macOS Keychain.

The current Map action opens an external `mapUrl`. There is no browser Party editor or browser/native state merge in the macOS release runtime.

## Import Flow

1. The member editor accepts one public build URL and requires a configured Local Qwen or OpenRouter provider.
2. Swift downloads and extracts bounded page text, then calls only the selected provider directly.
3. The structured response must match the import schema, including explicit point buy and bonuses.
4. Swift validates and normalizes the draft before creating a `BuildSummary`.
5. The reusable build is persisted locally and added to all character build pickers.
6. A member-specific import assigns it to that character after any required replacement confirmation. Import never changes roster membership.

There is no silent provider fallback, hosted sign-in, or import quota. Provider failures stay visible in Party, and a failed import does not save a partial build.

## Interaction Rules

- Selecting a different build applies its recommended creation values only after any destructive consequences are confirmed.
- Importing a build from a member editor assigns it to that member after validation and any replacement confirmation.
- "Respec" describes an upcoming BG3 recipe. "Reset character plan" is the destructive application action and always requires confirmation.
- Dead, Departed, Unavailable, Camp, and Not recruited remain distinct.
- Failed Party actions appear in Party, not only in Settings diagnostics.
- Four active members is a maximum, not a completion requirement.
- Current-step labels use the matched build-step level. Older fallback advice is explicitly labelled "Latest plan Lx."
- Imported builds remain advisory and visibly distinct from reviewed builds.

## Presentation Rules

- 9pt is the minimum native type size.
- Text and symbols carry meaning independently of color.
- The ability recipe uses a text table, not a segmented score bar.
- Point buy, +2/+1 bonuses, and final BG3 values are separate columns or rows.
- Every applied score source includes its gameplay modifier in the source ledger.
- Guidance board, member detail, ability progression, and roster management use the same terminology.

## Developer Workflow

Regenerate Party/build data after changing reviewed build, ability, or gear inputs:

```sh
cd backend
uv sync --extra dev
uv run python scripts/export-swift-resources.py
uv run pytest
```

Verify the native contracts and UI target:

```sh
cd ..
./scripts/macos/validate.sh
```

`mac/Tests/BG3AssistantTests/BuildImportTests.swift` covers deterministic import conversion and validation. Changes to point-buy rules must also keep `AbilityProgression`, generated reviewed setup data, Party presentation, and import schema behavior aligned.
