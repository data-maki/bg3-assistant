# BG3 Honor Assistant for Windows

> **Status: research and implementation plan only. There is no Windows binary to download yet.**
> Every installation or usage step below is labeled **Planned** until a signed build has passed the Windows/BG3 release gates.

BG3 Honor Assistant is planned as an overlay-only Honor Mode companion for Baldur’s Gate 3. It will show route guidance, party/build/loadout planning, act progress, and optional OpenRouter chat while you play.

It will not install a BG3 mod, inject into the game, read or edit saves, inspect game memory, or change game files.

## Planned system requirements

- Windows 11 x86-64/AMD64. Initial target: Windows 11 24H2 or newer; the supported floor will be rechecked before release.
- The 64-bit Windows version of Baldur’s Gate 3.
- BG3 in **Windowed** or **Borderless Windowed** mode. True exclusive full-screen is not supported by the planned non-injected overlay.
- Internet only for OpenRouter chat, build imports, external links, and updates.
- Optional microphone for speech-to-text.

“x86” in the port request is interpreted as x86-64/AMD64. A 32-bit build is not planned or needed for BG3.

The finished installer is intended to include its own .NET runtime and all guide assets. You should not need Visual Studio, developer tools, Python, Node, Ollama, a local model, or a separate server.

## Download and installation

**Planned — not available today.**

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

**Planned. OpenRouter will be optional; the local guide will work without AI chat.**

1. Create an OpenRouter account and API key from the [OpenRouter dashboard](https://openrouter.ai/keys).
2. In BG3 Honor Assistant, open **Settings > AI**.
3. Paste the key and select **Save key**.
4. Optionally select **Test connection**. This sends a small request and may use OpenRouter credits.

The app will call OpenRouter directly over HTTPS. It will not route your key through a BG3 Honor Assistant server. The key will be stored for your Windows user in Windows Credential Manager under `BG3HonorAssistant/OpenRouter`, not in the run database or logs.

The planned default model is `google/gemini-3.6-flash`, based on the OpenRouter catalog as of July 25, 2026. Model availability and pricing can change; the release process will verify the configured model before every build. Check [OpenRouter’s model page](https://openrouter.ai/google/gemini-3.6-flash) and your account limits for current pricing.

## First launch and permission prompts

**Planned.**

First launch will ask you to:

- start a fresh run or catch up a run already in progress;
- choose difficulty and spoiler depth;
- set party members and levels;
- use the guide alone or add an OpenRouter key;
- optionally start the assistant when you sign in to Windows.

Windows permission behavior:

- **Screen capture:** no prompt at launch. The Windows capture picker appears only after you select **Attach BG3 screenshot** in chat. You choose the BG3 window, Windows shows a capture border, and the app captures one frame.
- **Microphone:** no prompt at launch. Windows may request microphone access only after you press the mic button. Dictation may also require Windows Online speech recognition.
- **Startup:** disabled by default. Windows remains in control if you enable it.
- **Administrator:** not required and will not be requested.

If you deny capture or microphone access, typed chat and all local guide/planning features will remain available.

## Starting the overlay with BG3

**Planned.**

1. Start BG3 Honor Assistant. It will wait in the system tray.
2. Start Baldur’s Gate 3 in DirectX 11 or Vulkan.
3. Use Windowed or Borderless Windowed mode.
4. The overlay will appear when the BG3 window is detected and “Show overlay while BG3 is running” is enabled.

You will also be able to use **Launch BG3** from the tray for the Steam edition. GOG players can launch from GOG Galaxy or their normal shortcut.

If BG3 was started as administrator, restart it normally. BG3 Honor Assistant will not elevate itself to follow an elevated game.

The planned overlay includes:

- a compact animated pet, focus card, and reference density;
- Now and Route guidance with completion/skip/revisit state;
- multiple runs and mid-run catch-up;
- Party, reviewed/manual Builds, Loadout/Gear, and Act ledgers;
- optional grounded OpenRouter chat, screenshot attachment, and speech-to-text;
- Settings, diagnostics, startup control, legal notices, and external map/wiki links.

The current shared guide has Act 1 and Act 3 route content but no Act 2 checkpoints/walkthrough. The Windows app will label that gap; it will not invent Act 2 guidance.

## Updating

**Planned.**

- Microsoft Store installs will update through the Store.
- Signed beta installs will use Windows App Installer to check the official HTTPS feed when the app launches.
- Updates will preserve runs, settings, and the Credential Manager key.
- Database migrations will make a local recovery copy before a destructive schema change.

Do not download replacement executables from chat messages, mirrors, or unverified domains.

## Uninstalling

**Planned.**

1. To remove the API key, use **Settings > AI > Remove OpenRouter key**.
2. Open **Windows Settings > Apps > Installed apps**.
3. Find BG3 Honor Assistant and select **Uninstall**.

MSIX uninstall will remove the application and its local run data. The initial parity port does not include run export/import, so do not uninstall if you need to keep those runs. Windows Credential Manager is outside the app package, so a key can remain if you uninstall before removing it. In that case, open **Control Panel > Credential Manager > Windows Credentials** and remove `BG3HonorAssistant/OpenRouter`.

The app will not leave a BG3 mod, service, driver, scheduled task, firewall rule, model runtime, or game-file change.

## Troubleshooting

### There is no download

That is the current expected state. This repository contains research and a build plan, not a Windows release.

### The planned overlay does not appear

- Confirm BG3 is Windowed or Borderless Windowed.
- Confirm **Show overlay while BG3 is running** is on.
- Open the tray menu and select **Show Overlay**.
- Do not run BG3 as administrator.
- Check Diagnostics for a detected `bg3.exe` or `bg3_dx11.exe` window.

### Screenshot attachment is unavailable

- Make sure BG3 is visible and not minimized.
- Select the BG3 window in the Windows capture picker.
- Confirm Windows supports screen capture and that enterprise policy has not blocked it.
- HDR capture will be release-tested, but disabling HDR is a reasonable diagnostic—not a permanent requirement.

### Speech-to-text is unavailable

- Check **Settings > Privacy & security > Microphone**.
- Check **Settings > Privacy & security > Speech** for Online speech recognition.
- Confirm a supported microphone and Windows speech language are installed.
- Type your message instead; speech is optional.

### OpenRouter chat fails

- Confirm a key is saved and use **Test connection**.
- Check internet/proxy access to `https://openrouter.ai`.
- Check OpenRouter credits, limits, model status, and billing.
- Read the exact authentication, rate-limit, network, or model error in Diagnostics.

The app will not hide provider failures behind a fake offline chat answer.

### Windows warns about the installer

The stable goal is a Microsoft Store build. A newly signed direct beta may still have limited SmartScreen reputation. Verify the publisher, version, release page, and SHA-256. Do not disable Defender or install an unsigned/self-signed public build. Microsoft explains how SmartScreen reputation works for new signed applications ([SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).

## Privacy and security

Planned local data:

- runs, routes, party, builds, gear, acts, and settings in a local SQLite database;
- OpenRouter key in Windows Credential Manager;
- short redacted diagnostics logs with no key, prompt, or screenshot content.

Planned network data:

- chat text, selected guide context, recent in-memory chat history, and an optional attached screenshot go directly to OpenRouter when you press Send;
- build-import URLs are fetched only after you request an import;
- maps, wiki, legal, mail, and release links open in your default apps;
- Windows/Store/App Installer handles package updates.

Screenshots will be player-triggered, previewed, kept in memory, sent with one message, and then discarded. They will not be captured in the background or written to disk. Speech audio will use the Windows speech service to produce a draft and will not be sent to OpenRouter by this application. If Windows Online speech recognition is enabled, Microsoft may process that audio under its Windows privacy terms.

BG3 Honor Assistant will not:

- install or communicate with a BG3 mod;
- inspect process memory or inject code;
- read/edit saves or game files;
- install a driver/service or listen on a network port;
- require administrator access;
- download/run an AI model or local model server.

Report suspected security problems privately to the repository maintainers rather than posting keys, screenshots, or exploit details in a public issue. Never include an OpenRouter key in a report.

## Contributing

The implementation plan is in:

- [`research/feature-parity.md`](research/feature-parity.md)
- [`research/architecture.md`](research/architecture.md)
- [`research/dependencies-permissions.md`](research/dependencies-permissions.md)
- [`research/packaging-installation.md`](research/packaging-installation.md)
- [`research/implementation-plan.md`](research/implementation-plan.md)

Useful contributions before implementation starts:

- review a parity row against the current `/mac` source;
- test the planned overlay/capture harness on Windows 11 x64 with BG3 DirectX 11 or Vulkan;
- improve Windows accessibility, DPI, HDR, signing, or packaging test cases;
- report a missing requirement without proposing mod/injection integration.

Do not submit a Windows build that bundles Ollama, Python, Node, a local model/server, an unsigned public installer, or a BG3 mod.
