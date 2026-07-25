<p align="center">
  <img src="docs/images/app-logo.png" width="128" alt="BG3 Honor Mode Assistant shield">
</p>

<h1 align="center">BG3 Honor Mode Assistant</h1>

<p align="center"><strong>Keep your Honor run on track without tabbing out.</strong></p>

<p align="center">
  A native macOS overlay for the route's next move, fight risks, missable decisions,<br>
  party progression, and equipment plan. You play the game; the app keeps the plan in view.
</p>

<p align="center">
  <a href="#quick-start">
    <img src="https://img.shields.io/badge/Quick_start-macOS-B47A3C?style=for-the-badge&logo=apple&logoColor=white" alt="Quick start on macOS">
  </a>
  <br>
  <sub>macOS 14+ | Apple silicon | Beta | No mod or account required</sub>
</p>

<p align="center">
  <img src="docs/images/product-tour.gif" width="560" alt="Animated tour of the Now, Route, Party, and Loadout views">
</p>

> **Current beta coverage:** Act 1 route guidance is available. Act 3 is available for runs started or caught up there. Act 2 includes equipment and a public map handoff, but its route is not ready, so normal progression from Act 2 to Act 3 remains locked.

## Quick start

A notarized download is not available yet, so the one-click installer first builds the app on your Mac. No coding experience is required.

### What you need

- macOS 14 or later on Apple silicon
- An internet connection for the first build
- About 3 GB of free space for build files, plus 2.5 GB if you choose Local Qwen
- About 5-10 minutes for the first install

You do **not** need Git, Python, Homebrew, the full Xcode app, an Apple developer account, a mod manager, or Script Extender.

### Install without Git

1. [Download the project ZIP](https://github.com/data-maki/bg3-assistant/archive/refs/heads/main.zip), then double-click it to extract the `bg3-assistant-main` folder.
2. Open **Terminal** from Spotlight (`Command-Space`, then type `Terminal`).
3. Type `cd `, including the space, then drag the extracted folder into Terminal and press Return.
4. Paste the command below and press Return:

```sh
bash ./install-macos.sh
```

If macOS asks to install Command Line Tools, finish that installer and run the same command again. The assistant is then installed in `~/Applications` and opens automatically.

<details>
<summary><strong>Install with Git instead</strong></summary>

```sh
git clone https://github.com/data-maki/bg3-assistant.git
cd bg3-assistant
bash ./install-macos.sh
```

</details>

### First five minutes

1. Choose whether this is a fresh Honor run or one already in progress.
2. Choose **Local Qwen** for the simplest private setup, then download its 2.5 GB model. Or choose **OpenRouter** and enter your own API key.
3. Pick your active party, levels, and builds.
4. Click **Start Adventuring**, then launch Baldur's Gate 3.
5. Follow **Now** for the next action and use **Route**, **Party**, and **Loadout** when you need more detail.

The installer includes the guide and local AI runtime, verifies the app, and installs it to `~/Applications`. You do not need to leave Terminal open while playing. Run `bash ./install-macos.sh` again from the project folder to update.

Invited TestFlight testers can instead install through [TestFlight](https://apps.apple.com/app/testflight/id899247664). The guide, run planning, party, loadout, and act review work without an account; AI chat and public-URL build import require Local Qwen or OpenRouter.

## Why use it

**Know what matters now.** See the route's recommended action, the outcome to avoid, the risk and level, and the reason behind the recommendation. Mark it done, record a different outcome, or skip it yourself.

**See what opens next.** Route dependencies separate what is ready from what comes later. Deadlines, lockouts, unresolved consequences, and completed steps stay attached to the run instead of a pile of browser tabs.

**Keep the party on plan.** Each active character gets current-level build guidance, equipment picks, ownership, and contention warnings. Built-in builds also include exact creation and respec ability recipes.

| Current-level party guidance | Equipment planning |
| --- | --- |
| <img src="docs/images/overlay-party.png" alt="Party view showing level-five guidance for four active characters"> | <img src="docs/images/overlay-loadout.png" alt="Loadout view showing equipment picks and contested items"> |

## How a run works

1. Pick your active four, levels, and builds. You can also catch up a run that is already in progress.
2. Follow **Now** for the immediate recommendation or open **Route** to see the surrounding steps and blockers.
3. Confirm what happened. The next recommendation updates from your recorded progress and decisions.
4. Review equipment and unresolved consequences before advancing an act. Advancing locks that act's ledger inside the app; it does not change the BG3 save.

Nothing is inferred from the game. The app does not read saves or memory, and it never marks a fight, decision, or pickup complete on its own.

## More than a route checklist

- Save separate solo, co-op, and retry runs, each with its own party, decisions, equipment, and progress.
- Use a full roster with Active, Camp, and Unrecruited placement, including Withers hirelings.
- Open the native walkthrough and pickup plan, or hand off to the current act's public map.
- Ask guide-grounded questions from the overlay with optional speech input.
- Import one reusable build from a public URL, then assign it to the selected character.

Imported builds are AI-extracted drafts, not a legality guarantee. The importer derives a legal 27-point starting allocation, but you should review classes, spells, feats, equipment, and later progression against the source. Importing never changes party membership.

## Coverage and route assumptions

| Act | Route | Equipment | Map |
| --- | --- | --- | --- |
| Act 1 | Available | Available | Public map handoff |
| Act 2 | Not yet available | Available | Public Shadow-Cursed Lands handoff |
| Act 3 | Available for started/caught-up runs | Available | Public Baldur's Gate handoff |

The current route is opinionated: it favors a cautious, generally good-aligned run and preserving companion and rescue outcomes. Treat it as planning support, not a guarantee against patches, unusual choices, or Honor Mode variance.

## Privacy and permissions

This is not a BG3 mod. It does not install game files, read memory or saves, automate input, record gameplay, or require Script Extender. Core run and catalog data are stored in your Application Support directory.

The core guide and planner do not need AI or internet access. Public map handoffs require internet access.

Local Qwen runs on this Mac after its model download. OpenRouter sends the selected run context needed to answer a question, including relevant guide facts, party, progress, and outcomes, to `google/gemini-3-flash-preview`. Its API key is stored only in macOS Keychain. The app never silently switches providers. With Screen Recording permission, OpenRouter chat can also prepare one visible BG3-window screenshot. You can preview or remove it, and it is sent only when you send that message. Local Qwen does not accept screenshots. There is no background capture or recording loop.

Build import downloads readable text from the public URL on this Mac. Local Qwen processes it locally; OpenRouter receives the URL and extracted text. Imported drafts are validated and saved locally. Speech input requests microphone and Speech Recognition access, and macOS may use Apple's speech service when on-device recognition is unavailable.

## Build and contribute

Contributions are welcome, from route corrections and build data to Swift UI and app behavior. Keep changes focused on helping a player make the next decision; this project intentionally does not connect to BG3 through mods, memory, saves, or automated input.

### Developer quickstart

You need macOS 14 or later and Swift 6. Clone the repo, run the full native validation, then build and open the app:

```sh
git clone https://github.com/data-maki/bg3-assistant.git
cd bg3-assistant
./scripts/macos/validate.sh
./scripts/macos/build-app.sh
open "artifacts/macos/app/BG3 Honor Mode Assistant.app"
```

| What you want to change | Start here |
| --- | --- |
| Overlay UI or native behavior | `mac/BG3Assistant/` |
| Swift tests | `mac/Tests/` |
| Routes, builds, items, or guide facts | `data/` |
| Guide generation or backend tooling | `backend/` |
| Build and release automation | `scripts/macos/` |

Python 3.11+ and [`uv`](https://docs.astral.sh/uv/) are only required when changing guide data, its loaders, or backend tooling:

```sh
cd backend
uv sync --extra dev
uv run python scripts/export-swift-resources.py
uv run pytest -q
```

Before opening a pull request:

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) and keep the change focused.
2. Run `./scripts/macos/validate.sh`; run the backend tests too when changing `data/` or `backend/`.
3. Include a screenshot for visible UI changes.
4. Never commit `.env` files, API keys, player data, or generated QA artifacts. Use `.env.example` only as a template.

See the [architecture guide](docs/developers/ARCHITECTURE.md) for data flow and component ownership, and the [release guide](docs/developers/RELEASE.md) for packaging and signing.

## Project links

- [Contributing](CONTRIBUTING.md)
- [Architecture](docs/developers/ARCHITECTURE.md)
- [Release guide](docs/developers/RELEASE.md)
- [Security policy](SECURITY.md)

This is an unofficial community project and is not affiliated with Larian Studios.

## License

[MIT](LICENSE)
