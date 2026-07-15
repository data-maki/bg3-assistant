# Architecture

## Product boundary

The product is a native macOS in-game overlay. It presents one current action, one important risk, manual run progress, a focused character sheet, and guide-grounded chat. The local browser map is the only intentional external surface.

There are no BG3 mods, memory readers, save editors, automated inputs, periodic screenshots, or background recordings. Configured AI chat may attach one player-visible BG3-window screenshot to the next message.

## Runtime

```text
Bundled guide data
       |
Native SwiftUI overlay <-> SQLite run state
       |                       |
       +---- localhost API ----+
                    |
          Browser map + optional OpenRouter chat
```

- `mac/BG3Assistant`: menu-bar lifecycle, in-game overlay, party/loadout UI, chat, and native persistence.
- `backend/app`: guide parsing, readiness/chat grounding, localhost state bridge, and browser-map server.
- `data`: reviewed route, walkthrough, build, equipment, and marker inputs.
- `backend/app/static/map`: browser map and walkthrough implementation.

The native app starts and owns the packaged backend. The browser map and native overlay share run state through the same SQLite database.

## State authority

- Guide data is reviewed source material.
- Route recommendations are deterministic suggestions.
- Progress, outcomes, party status, and equipment ownership are player-confirmed state.
- AI prose cannot complete activities or replace guide facts.

## UI ownership

- `Now`: immediate action, risk, readiness, and progress controls.
- `Run`: route order, focus changes, resolved archive, and decision outcomes.
- `Party`: one-character carousel with level, build, status, and equipment.
- `Chat`: contextual overlay action with speech input; it is not a primary navigation tab.
- `Map`: explicit action that opens the local browser map.
