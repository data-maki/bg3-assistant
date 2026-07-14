# BG3 Honor Telemetry (optional)

This is a separately installed, read-only Script Extender bridge for the BG3 Honor Mode Assistant. The native companion remains complete when this mod is absent, disabled, stale, or incompatible.

This package is **third-party**, not a Larian-supported Mod.io mod. The external JSON channel depends on Script Extender APIs that the official Toolkit's Osiris runtime does not expose. Read [`PUBLISHING_AUDIT.md`](PUBLISHING_AUDIT.md) before distributing or attempting to publish it.

## Contract

- Writes a bounded JSON snapshot to `~/Library/Application Support/BG3HonorAssistant/telemetry/events.json`.
- Publishes combat, down/death/revive, roll, level, equipment, and rest events.
- Calls no Osiris mutation functions and performs no game input, save access, route completion, or party mutation.
- The companion treats the file as untrusted advisory context and falls back to Vanilla mode after eight seconds without a heartbeat.
- The player must still confirm every guide step.

## Important disclosure

This is still a BG3 mod. [Larian states that achievements are disabled while mods are active](https://forums.larian.com/ubbthreads.php?Number=952111&ubb=showflat), and game patches or Script Extender updates can break it. Keep **Use optional Live Events** off for a fully clean Honor run.

The macOS Script Extender is a community reverse-engineered project, not an official Larian or Norbyte macOS release. Do not install this bridge into an existing run until that dependency and this package have been validated against the exact game patch.

## Build

The source layout is ready for a BG3 package tool. On macOS, install the Apache-2.0 [`oliver`](https://gitlab.com/saghm/xiba) CLI (`cargo install oliver`), or use a compatible official Toolkit/Divine toolchain, then:

```zsh
./scripts/build-mod.sh
```

The script intentionally exits without creating a fake `.pak` when neither tool is available. Set `OLIVER=/absolute/path/to/oliver` or `DIVINE=/absolute/path/to/Divine` when it is not on `PATH`.

The current verified artifact is [`dist/BG3HonorTelemetry.pak`](dist/BG3HonorTelemetry.pak), SHA-256 `2e105cd5aafc1ac0c52c3357dc95de01ce0e4840792d3b8c838fad3ef1ce7244`. It parses with the expected UUID and metadata, and unpacking it reproduces `source/` byte-for-byte. It has intentionally not been installed into the current BG3 profile.

Run `./scripts/validate-publishing.sh` after rebuilding to check the package metadata, Script Extender config, Lua syntax when available, executable-file policy, and listing image dimensions. These are local artifact checks; they do not make the bridge eligible for Larian's official pipeline.

For app-only QA, simulate one event without touching BG3:

```zsh
./scripts/simulate-feed.py downed
```

Use `--duration 30` to keep the simulated feed fresh during a bounded UI smoke test.

Turn on **Use optional Live Events** in the companion to poll the feed. Turn it off or remove the JSON file to return to clean Vanilla behavior.
