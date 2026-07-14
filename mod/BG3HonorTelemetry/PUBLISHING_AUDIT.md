# BG3 Honor Telemetry publication audit

**Decision: do not upload the current package to Larian's supported Mod.io pipeline.**

The package is a valid third-party `.pak`, but its external telemetry channel is implemented with Script Extender Lua (`Ext.Osiris`, `Ext.IO`, and `Ext.Json`). Larian's supported scripted-mod path is Toolkit-authored Osiris. The official pipeline does not provide a documented Osiris file-system or socket API that can deliver structured events to a separate macOS process.

## What is ready

- Original source and UUID-owned `meta.lsx`.
- Read-only event listeners; no combat, input, save, entity-memory, or route-completion mutation.
- Versioned, bounded JSON contract with stale/malformed fallback in the companion.
- Reproducible `.pak` build and unpack/compare validation.
- Original 1280×720 listing art and drafted profile copy.
- Vanilla companion remains the default and requires no mod.

## Why official publication is blocked

1. **Unsupported transport.** The current bridge requires a third-party Script Extender runtime. It is not a Toolkit-authored Osiris project.
2. **No official external channel.** Official Osiris can react to game state, but Larian documents its trace as an Editor debugging log rather than a supported standalone telemetry API.
3. **Publisher tool unavailable here.** Larian's BG3 Toolkit is PC-only. This repository is being developed and tested on Apple silicon macOS, and no Windows VM or Toolkit installation is available.
4. **Runtime not proved.** The package has intentionally not been enabled in the player's clean Honor profile. Exact-patch event delivery and clean disable/uninstall behavior still require a deliberately modded test profile.
5. **Mac curation mismatch.** Mac in-game availability is limited to Toolkit-uploaded mods that pass Larian's additional testing. A community macOS Script Extender dependency cannot be represented as an auto-installed Mod.io dependency.

Uploading now would overstate compatibility and could create a package that scans successfully but cannot function for the intended Mac player.

## Release-safe paths

### A. Ship the current bridge as an optional third-party package

Use the existing `.pak` only for an explicitly modded test/release channel. Disclose the exact Script Extender dependency, supported BG3 patch, achievements impact, manual install/uninstall steps, and the unverified macOS runtime. Keep the main app fully functional in Vanilla mode.

### B. Build a separate official Mod.io edition

Keep the companion contract, but replace the filesystem transport with a Toolkit-supported in-game UI beacon that encodes a small, non-sensitive event snapshot. The existing two-second local ScreenCaptureKit loop can decode that beacon without cloud vision. This is the most credible official architecture, but it is a research candidate—not a verified capability—until built and tested in the Windows Toolkit.

Required proof before Mod.io upload:

1. Create a new project in the Windows BG3 Toolkit with this mod's UUID and original thumbnail.
2. Implement only Toolkit-supported Osiris/UI files; exclude `ScriptExtender/` entirely.
3. Build/reload story with zero warnings and test the beacon in a disposable modded save.
4. Confirm the macOS companion decodes the beacon after resize, UI-scale change, and game restart.
5. Publish through **Project Settings → Publish**, wait for automated scanning, complete the profile and dependency fields, and test the downloaded draft.
6. Request explicit user confirmation immediately before **Go live**.

## Account and tooling boundary

Authentication should use the existing linked Larian/Mod.io session. Credentials must never be copied into this repository, terminal history, listing copy, or test fixtures. The final public action is intentionally not automated without action-time confirmation.

## Primary references

- Larian, [Publishing a Mod](https://docs.baldursgate3.game/Getting_Started:_Publishing_a_Mod)
- Larian, [Creating a New Mod](https://docs.baldursgate3.game/Getting_Started:_Creating_a_New_Mod)
- Larian, [Modding Guidelines & FAQ](https://forums.larian.com/ubbthreads.php?Number=948625&ubb=showthreaded)
- Larian, [Playing With Mods](https://forums.larian.com/ubbthreads.php?Number=951934&ubb=showflat)
