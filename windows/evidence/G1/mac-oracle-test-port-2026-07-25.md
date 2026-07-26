# Mac oracle test port - 2026-07-25

## Inventory

The live Mac target has 47 XCTest methods. Six belong to the unreachable legacy backend
endpoint surface and are intentionally not ported. The remaining 41 behaviors now have
xUnit coverage:

| Mac fixture | Mac tests | Windows fixture | Result |
|---|---:|---|---|
| `RunSafetyTests.swift` | 14 | `Core.Tests/Route/RunSafetyTests.cs` | 14 pass |
| `ManualBuildTests.swift` | 11 | `Core.Tests/Models/ManualBuildTests.cs` | 11 pass |
| `OnboardingTests.swift` | 6 | `Core.Tests/Models/OnboardingTests.cs` | 6 pass |
| `RunCreationTests.swift` | 1 | `Core.Tests/Models/RunCreationTests.cs` | 1 pass |
| `ActLedgerTests.swift` | 2 | `Core.Tests/Models/ActLedgerTests.cs` | 2 pass |
| `BuildImportTests.swift` | 3 | `Core.Tests/Models/BuildImportTests.cs` | 3 pass |
| `GearLogicTests.swift` | 4 | `Core.Tests/Models/GearLogicTests.cs` | 4 pass |
| Total live behavior | 41 |  | 41 pass |

Ninety-nine additional Core tests cover Swift-compatible enum/date serialization,
legacy and current `HonorRun` snapshots, roster normalization and party-plan restore,
current-goal precedence and the exact Act 2 data-gap message, route encounter/activity
derivation, complete ability-progression/source semantics, shared-resource inventory,
and typed-chat prompt/scope/source/schema contracts. The Core suite therefore contains
140 passing tests.

The six omitted methods are exactly `BackendEndpointTests.swift`. They exercise the dead
local-backend endpoint/authenticator path that the Windows architecture forbids.

## Reviewed Windows adaptations

Four onboarding behaviors are direct equivalents. Two Mac tests describe functionality
that is forbidden in the Windows MVP:

- `testLocalModelCapabilitiesAreExplicit` is represented by
  `WindowsMvpExplicitlyExcludesLocalModels`.
- `testOllamaImageIsAttachedToLastMessage` is represented by
  `WindowsMvpExplicitlyExcludesImageMessages`.

Those negative tests enforce OpenRouter-only, typed-text-only behavior and also assert the
approved screenshot and microphone/speech exclusions. They do not claim Ollama or image
message parity.

## Generated spell catalog and media

[`../../tools/generate-spell-catalog.ps1`](../../tools/generate-spell-catalog.ps1)
mechanically converts the committed Mac spell oracle into the embedded Windows resource
[`../../src/BG3HonorAssistant.Core/Resources/spell-catalog.json`](../../src/BG3HonorAssistant.Core/Resources/spell-catalog.json).
The generated resource records source SHA-256
`7EB85795C5B2DD02D2344606F6BB60E10BBDCE781CC177CA62044631AD72962A`.

The manual-build tests cover 12 classes through level 12, multiclass propagation,
subclass-conditional choices, legal ability allocation, current spell facts, more than
1,000 catalog entries, stable artwork names, and presence of every referenced icon.

## Additional oracle and compatibility evidence

- `Serialization/HonorRunSerializationTests.cs` decodes a legacy Mac snapshot, seeds
  every missing companion exactly once, and round-trips all current party, gear, outcome,
  act, target, and modifier fields.
- `Serialization/JsonDefaultsTests.cs` proves Swift reference-date seconds and defensive
  ISO date input produce the same instants and that Windows writes the Swift-compatible
  numeric form.
- `Route/CurrentGoalTests.cs` proves target, Act-data availability, walkthrough,
  checkpoint, and completion precedence and enforces
  `Act 2 route is not available in this guide version`.
- `Route/RouteDerivationTests.cs` covers encounter classification and level-activity
  labeling without inventing route data.
- `Models/HonorRunBehaviorTests.cs`, `Models/AbilityProgressionTests.cs`, and
  `Models/AbilitySourceRulesTests.cs` cover the full roster seed/status cap, complete
  party-plan snapshot, equipment ownership, story outcomes, permanent/consumable/
  equipment/temporary modifiers, source ownership, act/level gates, and unique-across-
  party behavior.

## Persistence and shared-resource evidence

The Infrastructure suite contains 76 passing tests. Its G1 persistence/resource coverage
includes:

- exactly one active run;
- atomic snapshot plus revision writes and 20-revision pruning;
- fallback to the newest valid revision;
- JSON settings;
- imported builds in SQLite;
- schema v1-to-v2 migration;
- a timestamped pre-migration recovery copy;
- transaction rollback and usable source/backup after a failed migration;
- preserving corrupt database bytes for explicit recovery;
- invalid JSON rejection before database creation; and
- the patched SQLite runtime floor; and
- a typed decode/re-encode/decode of the committed guide that preserves every route
  decision, incident protocol, risk/reward record, item fact, act summary, gear field,
  target ability score, and ability source.

The remaining Infrastructure tests cover the G4 public-network, OpenRouter, and secure
build-import contracts and are described separately in
[`../G4/typed-openrouter-import-2026-07-25.md`](../G4/typed-openrouter-import-2026-07-25.md).

Machine-readable results:

- [`../automated-results/BG3HonorAssistant.Core.Tests-2026-07-25.trx`](../automated-results/BG3HonorAssistant.Core.Tests-2026-07-25.trx)
- [`../automated-results/BG3HonorAssistant.Infrastructure.Tests-2026-07-25.trx`](../automated-results/BG3HonorAssistant.Infrastructure.Tests-2026-07-25.trx)

## Evidence boundary

This proves the enumerated domain fixtures, compatibility snapshots, typed guide
round-trip, and persistence contracts. G1 remains pending until the remaining pure
gear-path/pickup, act-transition, and party mutation rules have equivalent tests and the
final resource/package inventory is tied to the rebuilt artifact. It does not prove G2/G3
UI parity.
