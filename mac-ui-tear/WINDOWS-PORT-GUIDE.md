# Windows screenshot reuse guide

This guide decides which macOS captures the Windows app copies exactly and which
captures require a deliberate platform/product adaptation.

The two folders are implementation requirements:

- [`screenshots/clone-1-to-1/`](screenshots/clone-1-to-1/) contains 47 screens.
  Copy their dimensions, hierarchy, spacing, typography, colors, borders, artwork,
  visible states, navigation, and behavior from `/mac`.
- [`screenshots/windows-adapted/`](screenshots/windows-adapted/) contains 12 screens.
  Keep the Mac shell and visual language, but apply only the differences listed
  below.

## Clone 1-to-1

These groups require no Windows redesign:

- Welcome, difficulty, spoilers, party setup, and catch-up onboarding.
- Minimal, Focus, and Reference overlays.
- Now, Route, route detail, skip/revisit, filters, and Act 3 catch-up.
- Party, member detail, build comparison, manual builds, roster, abilities, and
  reset confirmation.
- Loadout, gear detail, targets, equipped state, and build import.
- Act 1/2/3 ledgers.
- Runs, Support, Legal, Diagnostics entry points, and new-run confirmation.

“Clone 1-to-1” still allows invisible native substitutions such as Windows window
placement, Credential Manager, startup tasks, and URL launching. Those substitutions
must not change the captured layout or product behavior.

## Windows-adapted screens

| PNG | Windows implementation |
| --- | --- |
| [06 - no AI selected](screenshots/windows-adapted/06-onboarding-ai-none.png) | Keep the same card, size, title hierarchy, progress, and buttons. Replace the three Mac provider rows with two choices: **Guide only** and **OpenRouter**. Explain that the guide works offline and AI is optional. Do not mention local models or screenshots. |
| [07 - Gemma selected](screenshots/windows-adapted/07-onboarding-ai-gemma.png) | Mac-only state. Do not create a Gemma row, download button, progress state, or model-storage UI on Windows. The selected-card styling may be reused for the Windows OpenRouter choice. |
| [08 - Qwen installed](screenshots/windows-adapted/08-onboarding-ai-qwen.png) | Mac-only state. Do not create a Qwen row, installed status, local runtime, or text-only local-provider state. |
| [09 - OpenRouter selected](screenshots/windows-adapted/09-onboarding-ai-openrouter.png) | Keep the selected OpenRouter card and status placement. Replace **Keychain** with **Windows Credential Manager**. Describe OpenRouter as typed chat and build import only; remove every claim about sending or attaching screenshots. |
| [12 - fresh-run ready](screenshots/windows-adapted/12-onboarding-ready.png) | Keep the layout and actions. Replace “this Mac” with “this PC,” “menu-bar shield” with “system-tray icon,” and “waits in the menu bar” with “waits in the system tray.” Keep **Start at login** and **Start Adventuring**. |
| [40 - empty screenshot-capable chat](screenshots/windows-adapted/40-chat-empty.png) | Keep the shell, context chips, empty state, quick prompts, and composer. Remove the screenshot error/status row, Retry action, screenshot capability, and microphone button. The text composer occupies the freed width. |
| [41 - OpenRouter Settings](screenshots/windows-adapted/41-settings.png) | Keep the Settings cards and General section. OpenRouter is fixed, so remove the provider picker. Show the Windows pinned model, configured/not-configured state, and Save/Replace/Test/Remove controls. Replace **Keychain** with **Windows Credential Manager**. |
| [45 - Qwen Settings](screenshots/windows-adapted/45-settings-qwen-provider.png) | Mac-only state. Do not create a local-provider picker, model-installed status, runtime controls, or download controls. Windows has only the OpenRouter configured/unconfigured states derived from screen 41. |
| [48 - Qwen text-only chat](screenshots/windows-adapted/48-chat-qwen-text-only.png) | Use only as a layout reference for empty typed chat. Remove the Qwen notice, screenshot-provider recommendation, screenshot controls, and microphone button. Windows chat is always typed OpenRouter chat when configured. |
| [49 - chat loading](screenshots/windows-adapted/49-chat-qwen-loading.png) | Keep the submitted-message position, disabled/loading behavior, context chips, and quick prompts. The request goes to OpenRouter. Remove the Qwen/screenshot notice and microphone button. |
| [50 - chat response](screenshots/windows-adapted/50-chat-qwen-response.png) | Keep the message cards, source chips, scrolling, quick prompts, and composer. The answer is from OpenRouter. Remove the Qwen/screenshot notice and microphone button. |
| [56 - mid-run ready](screenshots/windows-adapted/56-onboarding-midrun-ready.png) | Apply the same wording substitutions as screen 12: PC, system-tray icon, and waits in the system tray. Preserve the seven-step progress and all other layout/behavior. |

## Windows AI and chat result

```text
Onboarding
├─ Guide only
└─ OpenRouter
   └─ key stored in Windows Credential Manager

Chat
├─ typed input only
├─ Current | Route | Party scope
├─ quick prompts, loading, answer, errors, and sources
└─ no screenshot, capture, microphone, audio, speech, or local model
```

## Source rule

For both folders, the PNG is the visual oracle and the linked Swift source in
[`SOURCE-ASSET-MAP.md`](SOURCE-ASSET-MAP.md) is the behavior oracle. A Windows
screen is not complete if it looks correct but uses placeholder behavior.
