# Contributing to the Windows app

The Windows UI is organized by player-facing feature. A change to one screen
should normally stay inside one `Screens/<Feature>/` folder.

```text
src/BG3HonorAssistant.App/
  Application/              controller and product-operation adapters
  Shell/                    window chrome, navigation, refresh orchestration
  Screens/
    Now/
    Route/
    Party/                  member, roster, ability, build, and import components
    Loadout/
    Act/
    Chat/
    Settings/
  Components/               onboarding and shared confirmation surfaces
  Overlay/                  companion overlay window and coordinator
  UI/                       theme, artwork lookup, and pet rendering
```

## Ownership rule

Each screen folder contains:

- `<Feature>View.xaml`: the visible hierarchy for that feature.
- `<Feature>View.xaml.cs`: only typed UI-event forwarding.
- `MainWindow.<Feature>.cs`: rendering, local interaction state, and calls to
  `AssistantController`.
- `Components/`: nested surfaces only when the parent screen is still too large.

The shell owns window dimensions, top navigation, application-wide refresh order,
and cross-screen confirmation hosting. Do not put feature-specific rows, buttons,
or product decisions back into `Shell/MainWindow.xaml`.

The data flow stays direct:

```text
XAML control
  -> feature view event
  -> screen-owned MainWindow partial
  -> AssistantController
  -> persisted Core model
  -> screen refresh
```

This deliberately avoids a new MVVM framework, service locator, or parallel state
model. `AssistantController` remains the only product-operation boundary.

## Before changing a screen

1. Find its row in `research/ui-replica-ledger.md`.
2. Compare the numbered PNG under
   `../mac-ui-tear/screenshots/clone-1-to-1/` or
   `../mac-ui-tear/screenshots/windows-adapted/` with the full Swift view and
   action owner named by that row.
3. Make the smallest change inside the owning screen folder.
4. Recheck the exact window size, disabled state, confirmation, persistence, and
   navigation result.
5. Keep intentional Windows differences limited to the ledger: OpenRouter,
   Credential Manager, system tray/startup, and typed chat.

Do not add local models, Ollama, screenshot capture, microphone/audio/speech
controls, BG3 mods, process injection, or duplicated artwork. All artwork comes
from repository-root `Resources/`.

## Adding a control

Add the XAML control and its handler to the owning view. Forward the event in that
view’s code-behind, implement the action in the adjacent
`MainWindow.<Feature>.cs`, and update the corresponding ledger evidence. If the
change needs another feature, expose one narrow navigation or confirmation action
through the shell instead of reaching into the other feature’s controls.

Windows runtime screenshots remain the final rendering check. On non-Windows
hosts, at minimum verify that every XAML file parses, every declared handler
exists in its own code-behind, every forwarded host action resolves, all resource
keys exist, and `git diff --check` passes. Pull requests also compile the app on a
Windows runner; this is the required guard against broken XAML name scopes or C#
partial-class wiring.
