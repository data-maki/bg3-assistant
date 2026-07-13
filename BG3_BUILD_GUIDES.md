# BG3 Honor Mode build guide data

The assistant treats each linked guide as a separate, versioned plan. It must never silently combine the three Swords Bard variants.

The detailed normalized data lives in:

- `data/build_overview.tsv` — role, final split, ability scores, play pattern, and Honor compatibility.
- `data/build_levels.tsv` — every character-level decision and the tactical change unlocked at that level.
- `data/build_gear.tsv` — priority equipment with act, map region, acquisition instructions, known coordinates, and source.

## Spreadsheet presentation

Create one tab per build/package. Each tab must contain, in this order:

1. A compact build summary and Honor Mode warning.
2. The level-by-level progression for only that build.
3. The equipment route for only that build, sorted by act and priority.

Do not use a combined player-facing build-details tab. The normalized TSV files remain the machine-readable source of truth.

## Safety rules

1. Do not expose Lockadin as an Honor Mode build; use the requested Flamadin plan instead.
2. Shadow Blade is equipment, not a standalone build; use the requested Bladesinger plan instead.
3. `SB-A1` is labeled assistant synthesis because the linked EIP page contains too little build text to support a source-attributed level plan.
4. Gear locations without verified coordinates retain `-`; the overlay must not invent a map marker.
5. The recommendation engine should select a build version explicitly and log any respec boundary before suggesting the next level.
