# BG3 Honor Assistant for Windows

> **Status: experimental. There is no signed Windows release to download yet.**
> The ARM64 app and development MSIX were installed and exercised only in a Windows 11 Parallels VM on Apple silicon at 200% display scaling. They have not been tested on Intel/AMD hardware or a native Windows PC. Controlled `bg3.exe` windows were used instead of the live game.

BG3 Honor Assistant is an overlay-only companion for Baldur’s Gate 3. It shows route guidance, party/build/loadout planning, act progress, and optional OpenRouter chat while you play.

It will not install a BG3 mod, inject into the game, read or edit saves, inspect game memory, or change game files.

## Experimental system requirements

- Windows 11 ARM64 in Parallels for the currently exercised build. Windows 11 x64/AMD64 remains unverified on native hardware.
- The 64-bit Windows version of Baldur’s Gate 3.
- BG3 in **Windowed** or **Borderless Windowed** mode. True exclusive full-screen is not supported by the non-injected overlay.
- Internet only for OpenRouter chat, build imports, external links, and updates.

Windows releases are separate, self-contained `arm64`/`win-arm64` and `x64`/`win-x64` MSIX packages. 32-bit x86, neutral MSIX identities, AnyCPU native payloads, and Arm64EC are unsupported.

The package includes its own .NET runtime and guide assets. A future signed player release will not require Visual Studio, developer tools, Python, Node, Ollama, a local model, or a separate server.

## Download and installation

**Not available to players today.** The repository can build development MSIX packages, but no signed release artifact is published.

The intended stable installation is through the Microsoft Store:

1. Open the verified BG3 Honor Assistant Store listing.
2. Select **Install**.
3. Select **Open**.

The intended beta installation is a signed App Installer download:

1. Download `BG3HonorAssistant.appinstaller` from the repository’s canonical release page.
2. Open it with Windows App Installer.
3. Confirm the displayed publisher and source, then select **Install**.
4. Select **Launch**.

No public release will ask you to enable Developer Mode, import a self-signed certificate, run PowerShell, or disable Windows security. Microsoft documents App Installer as a built-in Windows installation path ([App Installer](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-root)).

## OpenRouter key setup

OpenRouter is optional; the local guide works without AI chat.

1. Create an OpenRouter account and API key from the [OpenRouter dashboard](https://openrouter.ai/keys).
2. In BG3 Honor Assistant, open **Settings > AI**.
3. Paste the key and select **Save key**.
4. Optionally select **Test connection**. This sends a small request and may use OpenRouter credits.

The app will call OpenRouter directly over HTTPS. It will not route your key through a BG3 Honor Assistant server. The key will be stored for your Windows user in Windows Credential Manager under `BG3HonorAssistant/OpenRouter`, not in the run database or logs.

The app pins `google/gemini-3.6-flash`. Model availability and pricing can change; the release process must verify the configured model before every build. Check [OpenRouter’s model page](https://openrouter.ai/google/gemini-3.6-flash) and your account limits for current pricing.

## First launch and permission prompts

First launch will ask you to:

- start a fresh run or catch up a run already in progress;
- choose difficulty and spoiler depth;
- set party members and levels;
- use the guide alone or add an OpenRouter key;
- optionally start the assistant when you sign in to Windows.

Windows permission behavior:

- **Startup:** disabled by default. Windows remains in control if you enable it.
- **Administrator:** not required and will not be requested.

The Windows MVP has no screenshot capture, clipboard-image ingestion, microphone,
speech-recognition, or dictation feature and requests none of those permissions.

## Starting the overlay with BG3

1. Start BG3 Honor Assistant. It will wait in the system tray.
2. Start Baldur’s Gate 3 in DirectX 11 or Vulkan.
3. Use Windowed or Borderless Windowed mode.
4. The overlay will appear when the BG3 window is detected and “Show overlay while BG3 is running” is enabled.

You can also use **Launch BG3** from the tray for the Steam edition. GOG players can launch from GOG Galaxy or their normal shortcut.

If BG3 was started as administrator, restart it normally. BG3 Honor Assistant will not elevate itself to follow an elevated game.

The overlay includes:

- a compact animated pet, focus card, and reference density;
- Now and Route guidance with completion/skip/revisit state;
- multiple runs and mid-run catch-up;
- Party, reviewed/manual Builds, Loadout/Gear, and Act ledgers;
- optional general BG3 chat that uses run and guide context only when relevant;
- Settings, diagnostics, startup control, legal notices, and external map/wiki links.

The current shared guide has Act 1 and Act 3 route content but no Act 2 checkpoints/walkthrough. The Windows app will label that gap; it will not invent Act 2 guidance.

## Updating

Development-package upgrades preserved runs and settings in the Parallels test. Public updates are unavailable until a signed release exists.

- Microsoft Store installs will update through the Store.
- Signed beta installs will use Windows App Installer to check the official HTTPS feed when the app launches.
- Updates will preserve runs, settings, and the Credential Manager key.
- Database migrations will make a local recovery copy before a destructive schema change.

Do not download replacement executables from chat messages, mirrors, or unverified domains.

## Uninstalling

1. To remove the API key, use **Settings > AI > Remove OpenRouter key**.
2. Open **Windows Settings > Apps > Installed apps**.
3. Find BG3 Honor Assistant and select **Uninstall**.

MSIX uninstall will remove the application and its local run data. The initial parity port does not include run export/import, so do not uninstall if you need to keep those runs. Windows Credential Manager is outside the app package, so a key can remain if you uninstall before removing it. In that case, open **Control Panel > Credential Manager > Windows Credentials** and remove `BG3HonorAssistant/OpenRouter`.

The app will not leave a BG3 mod, service, driver, scheduled task, firewall rule, model runtime, or game-file change.

## Troubleshooting

### There is no download

That is the current expected state. This repository contains research, implementation source, tests, and development packaging, but not a signed Windows release.

### The overlay does not appear

- Confirm BG3 is Windowed or Borderless Windowed.
- Confirm **Show overlay while BG3 is running** is on.
- Open the tray menu and select **Show Overlay**.
- Do not run BG3 as administrator.
- Check Diagnostics for a detected `bg3.exe` or `bg3_dx11.exe` window.

### OpenRouter chat fails

- Confirm a key is saved and use **Test connection**.
- Check internet/proxy access to `https://openrouter.ai`.
- Check OpenRouter credits, limits, model status, and billing.
- Read the exact authentication, rate-limit, network, or model error in Diagnostics.

The app will not hide provider failures behind a fake offline chat answer.

### Windows warns about the installer

The stable goal is a Microsoft Store build. A newly signed direct beta may still have limited SmartScreen reputation. Verify the publisher, version, release page, and SHA-256. Do not disable Defender or install an unsigned/self-signed public build. Microsoft explains how SmartScreen reputation works for new signed applications ([SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).

## Privacy and security

Local data:

- runs, routes, party, builds, gear, acts, and settings in a local SQLite database;
- OpenRouter key in Windows Credential Manager;
- short redacted diagnostics logs with no key or prompt content.

Network data:

- typed chat text, selected guide context, and recent in-memory chat history go directly to OpenRouter when you press Send;
- build-import URLs are fetched only after you request an import;
- maps, wiki, legal, mail, and release links open in your default apps;
- Windows/Store/App Installer handles package updates.

BG3 Honor Assistant will not:

- install or communicate with a BG3 mod;
- inspect process memory or inject code;
- read/edit saves or game files;
- capture screenshots, read clipboard images, or request microphone access;
- install a driver/service or listen on a network port;
- require administrator access;
- download/run an AI model or local model server.

Report suspected security problems privately to the repository maintainers rather than posting keys, screenshots, or exploit details in a public issue. Never include an OpenRouter key in a report.

## Contributing

Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) for the screen-owned folder
structure, UI data flow, and the smallest safe way to change a feature.

The implementation plan is in:

- [`research/feature-parity.md`](research/feature-parity.md)
- [`research/architecture.md`](research/architecture.md)
- [`research/dependencies-permissions.md`](research/dependencies-permissions.md)
- [`research/packaging-installation.md`](research/packaging-installation.md)
- [`research/implementation-plan.md`](research/implementation-plan.md)

Useful contributions during implementation:

- review a parity row against the current `/mac` source;
- test native ARM64 and x64 controlled overlay hosts across supported display/DPI configurations;
- label x64 Windows CI, x64-on-ARM64 emulation, physical ARM64, and physical native-x64 evidence separately;
- improve Windows accessibility, DPI, signing, or packaging test cases;
- report a missing requirement without proposing mod/injection integration.

Do not submit a Windows build that bundles Ollama, Python, Node, a local model/server, an unsigned public installer, or a BG3 mod.
