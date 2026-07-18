<p align="center">
  <img src="docs/images/app-logo.png" width="180" alt="HM shield logo for BG3 Honor Mode Assistant">
</p>

# BG3 Honor Mode Assistant

A quiet macOS overlay for keeping an Honor Mode run on track without leaving Baldur's Gate 3.

![The Now view showing the current danger, outcome to avoid, recommended action, and progress controls](docs/images/overlay-now.png)

See the next safe action, check the risk before a fight, manage each companion's build, and mark progress yourself. The app stays in the menu bar and opens over BG3 only when you need it.

**This is not a BG3 mod.** It does not install game files, read memory or saves, automate input, record gameplay, or require Script Extender.

## What it does

- **Now** keeps the current danger, outcome to avoid, recommended action, and Done/Skip controls in one place.
- **Run** provides focused reviewed routes for Acts 1 and 3, with decisions, missable warnings, deadlines, and a resolved archive.
- **Party** leads with what each active character should take and do at their current level, with roster, build, respec, and Withers setup on focused detail pages.
- **Loadout** focuses on one active character at a time, including current-act equipment and public build imports.
- **Act** reviews obtained or missed equipment, locks the previous act, and advances the run deliberately.
- **Map** opens the local Act 1 walkthrough map or the current act's public map reference.
- **Chat** answers questions from the reviewed guide and your current run, with optional speech input and AI.

| In-game guidance | Guide-grounded chat |
| --- | --- |
| ![The Now view showing the current recommendation](docs/images/overlay-now.png) | ![The chat view answering a guide-grounded question about the current run](docs/images/overlay-chat.png) |

## Install the app bundle

Requirements: macOS 14 or later on Apple silicon. Building the bundle also needs Xcode 16 or its Command Line Tools (Swift 6) and [`uv`](https://docs.astral.sh/uv/), which provides the Python 3.11+ toolchain on its own.

```sh
git clone https://github.com/data-maki/bg3-assistant.git
cd bg3-assistant/mac
./scripts/build-app.sh
mv "BG3 Honor Mode Assistant.app" /Applications/
```

The script packages the Python service into a standalone backend, builds the Swift overlay in release mode, and assembles a codesigned **BG3 Honor Mode Assistant.app** (using your Developer ID or Apple Development identity when available, ad-hoc otherwise). The first build takes a few minutes; the script prints the finished bundle path when done.

Once installed, the app is self-contained: the bundled local service starts and stops with it, and playing needs no terminal, Python installation, mod manager, or Script Extender.

Invited TestFlight testers can skip the build: install [TestFlight from the Mac App Store](https://apps.apple.com/app/testflight/id899247664), accept the tester invite, and install **BG3 Honor Mode Assistant** from TestFlight.

## Set up

1. Open **BG3 Honor Mode Assistant** from Applications. The HM shield appears in the macOS menu bar.
2. Open **Settings** from the shield menu and keep or decline **Launch at Login**.
3. AI chat, screenshot questions, and build imports work out of the box — the released app ships with its own AI access. The guide itself is fully local and works without any network account.
4. Optional: allow microphone access for speech input and Screen Recording for the one-shot chat screenshot. Both can be declined and chat keeps working.

## Launch and play

1. Start Baldur's Gate 3 yourself, or use **Launch BG3** from the shield menu. The overlay stays out of the way until you show it from the menu bar.
2. Move through **Now**, **Run**, **Party**, **Loadout**, and **Act**. Nothing is marked complete until you confirm it.
3. Use the map icon for the current act map or the chat icon to ask about the active reviewed route.

## Keep separate Honor runs

Name and save multiple attempts, including solo and co-op campaigns. Each run keeps its own route progress, decisions, party, builds, and equipment. Switch the active run from the shield menu's **Run** submenu, or create and rename runs in the overlay's **Settings** view.

## Import a reusable build

Paste one public build URL from a character's **Party → Build** section. Gemini 3 Flash converts the guide into one validated reusable build, derives a legal 27-point creation recipe, assigns it after confirmation, and adds it to every character's build picker. Importing never changes party membership.

Reviewed builds show an exact BG3 table for character creation and every Withers respec: point-buy values, the distinct +2/+1 bonuses, final values to enter, first class, and class order. A source ledger explains later ASIs, feats, unique permanent rewards, equipment setters, and consumables. Equipment follows confirmed Loadout ownership; one-time rewards and elixirs enforce their party and timing rules. **Reset character plan** is separate from respec guidance, states everything it removes, requires confirmation, and can be undone. The Withers roster includes all 12 predefined hirelings with legal class spreads.

## AI features and screenshots

Chat has two modes:

- **Guide-only:** returns deterministic answers from the reviewed route and current player-confirmed state, with no network dependency.
- **OpenRouter AI:** chat and build imports use the app's bundled [OpenRouter](https://openrouter.ai/) access; there is nothing to configure.

When OpenRouter AI is configured, opening chat prepares one current BG3-window screenshot for the next message. The attachment is visible in chat, opens as a preview, and can be removed before sending. It is sent to OpenRouter only with that message. The overlay is excluded because the app captures the BG3 window directly.

There is no periodic capture, background vision loop, video recording, or silent upload. Chat and speech input continue to work if you remove the screenshot or decline Screen Recording permission.

Run state stays in your Application Support directory, and the bundled service listens only on `127.0.0.1`. The app's OpenRouter credential lives inside the bundled backend and is never written to user settings or the run database.

For a build import, the local service downloads the public URL and sends the extracted page text to OpenRouter. Private-network URLs, credential-bearing URLs, oversized pages, and unsupported file types are rejected. No API key is stored in the custom-build database or sent to the source website.

## Act 1 map

![The local Act 1 walkthrough and pickup map](docs/images/act-one-map.png)

The browser map shares the active run's manual progress and party equipment. It is the only separate app surface; normal planning and chat stay in the native in-game overlay.

## Act transitions

The **Act** tab is an irreversible gate. Before leaving an act, review every relevant active-party equipment item as obtained or missed and explicitly accept unresolved route consequences. Advancing locks that act's ledger and loads the next act's separate database.

## Current scope

The current guide includes reviewed Act 1 and Act 3 routes, act-scoped readiness and chat grounding, imported custom builds, named Honor runs, party and equipment state, the local Act 1 browser map, and public map handoffs for later acts. Act 2 equipment and map references are included, but its route is still research-only. The Act 2 to Act 3 gate therefore stays locked during normal progression even though the Act 3 guide is app-ready.

Treat the guide as planning support, not a guarantee against game patches, player choices, or Honor Mode variance. This is an unofficial community project and is not affiliated with Larian Studios.

## Contributing

Technical contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [architecture overview](docs/developers/ARCHITECTURE.md), keep pull requests focused, source guide-data corrections, and describe local verification. Internal tests and generated QA artifacts are intentionally excluded from public Git.

Good next milestones:

- Convert the reviewed Act 2 research into tested route data, plus a local Act 2 map
- TestFlight feedback, release automation, and a public beta invite
- Accessibility, keyboard-navigation, and first-run onboarding passes
- Localization-ready guide and interface strings
- Stronger deterministic chat evaluation and screenshot-attachment coverage

Security reports should follow [SECURITY.md](SECURITY.md). Release maintainers can use [docs/developers/RELEASE.md](docs/developers/RELEASE.md).

## License

[MIT](LICENSE)
