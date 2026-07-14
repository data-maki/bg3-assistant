# Desires

## 2026-07-13 — BG3 official publishing environment

- A disposable Windows BG3 Toolkit environment is required to create, compile, test, and upload a genuinely official Mod.io edition; the current Apple-silicon host cannot run Larian's PC-only Toolkit.
- Signed-in Chrome automation requires the ChatGPT Chrome Extension in the selected profile. On this machine it is enabled in Profile 3, while the selected Default profile has no extension, so authenticated Mod.io inspection cannot connect until the user selects Profile 3 or enables the extension in Default.

## 2026-07-13

- An authenticated Google Sheets document-control session with workbook import support would let the verified XLSX replace or extend the live guide without brittle canvas interaction or requiring the user's normal browser profile.
- A native desktop-control bridge that can attach to Metal games in borderless fullscreen and expose screenshots plus coordinate input under an explicit per-action scope would allow automated verification of BG3 custom-marker dialogs without falling back to unrelated OS automation.
- The in-app browser pointer-move action should update real DOM `:hover` state so local UI hover treatments can be visually asserted rather than inferred from the shared hover/focus CSS rule.

## 2026-07-12

- The desktop-control bridge lists the running BG3 app (`com.larian.bg3`) but cannot attach to its Metal window by display name, bundle ID, or app path. A game-window-compatible input/screenshot bridge would allow the final positive map-open acceptance check without asking the player to open the map manually.
