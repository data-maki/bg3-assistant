using System.ComponentModel;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Navigation;
using BG3HonorAssistant.App.UI;
using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Overlay;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Windows.Credentials;
using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Shell;
using BG3HonorAssistant.Windows.Startup;
using Application = System.Windows.Application;
using Brush = System.Windows.Media.Brush;
using ComboBox = System.Windows.Controls.ComboBox;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    private void StartOnboarding()
    {
        onboardingIndex = 0;
        onboardingMode = OnboardingMode.Fresh;
        onboardingDifficulty =
            controller.Run.Difficulty ?? RunDifficulty.Honour;
        onboardingReveal =
            controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything;
        onboardingCatchUpCheckpointId = null;
        onboardingUseOpenRouter = openRouterKeyConfigured;
        onboardingSteps = OnboardingFlow.Steps(onboardingMode);
        Onboarding.OnboardingPanel.Visibility = Visibility.Visible;
        ShowOnboardingStep();
    }

    private void ShowOnboardingStep()
    {
        var step = onboardingSteps[onboardingIndex];
        var panels = new FrameworkElement[]
        {
            Onboarding.OnboardingWelcomePanel,
            Onboarding.OnboardingDifficultyPanel,
            Onboarding.OnboardingSpoilersPanel,
            Onboarding.OnboardingAiPanel,
            Onboarding.OnboardingPartyPanel,
            Onboarding.OnboardingCatchUpPanel,
            Onboarding.OnboardingReadyPanel,
        };
        foreach (var panel in panels)
        {
            panel.Visibility = Visibility.Collapsed;
        }

        Width = 430D;
        Height = step switch
        {
            OnboardingStep.Welcome => 350D,
            OnboardingStep.Difficulty => 560D,
            _ => 470D,
        };
        Onboarding.OnboardingStepText.Text =
            $"Step {onboardingIndex + 1} of {onboardingSteps.Count}";
        Onboarding.OnboardingProgressDotsText.Text = string.Join(
            " ",
            Enumerable.Range(0, onboardingSteps.Count)
                .Select(index => index == onboardingIndex ? "━" : "•"));
        Onboarding.OnboardingFooter.Visibility = step == OnboardingStep.Welcome
            ? Visibility.Collapsed
            : Visibility.Visible;
        Onboarding.OnboardingBackButton.IsEnabled = onboardingIndex > 0;
        Onboarding.OnboardingNextButton.IsEnabled =
            OnboardingFlow.AllowsAdvance(step, onboardingDifficulty);
        switch (step)
        {
            case OnboardingStep.Welcome:
                Onboarding.OnboardingTitleText.Text = "Well Met, Adventurer";
                Onboarding.OnboardingBodyText.Text =
                    "BG3 Overlay floats above Baldur's Gate 3. Tell it whether this is a new adventure or a run already in progress.";
                Onboarding.OnboardingWelcomePanel.Visibility = Visibility.Visible;
                break;
            case OnboardingStep.Difficulty:
                Onboarding.OnboardingTitleText.Text = "Choose Your Difficulty";
                Onboarding.OnboardingBodyText.Text =
                    "BG3 Overlay is built for Balanced, Tactician, and Honour Mode runs. Pick the difficulty you are actually playing.";
                Onboarding.OnboardingDifficultyPanel.Visibility = Visibility.Visible;
                UpdateOnboardingDifficultyState();
                Onboarding.OnboardingNextButton.Content = "Use BG3 Overlay  ›";
                break;
            case OnboardingStep.Spoilers:
                Onboarding.OnboardingTitleText.Text = "How Far Ahead?";
                Onboarding.OnboardingBodyText.Text =
                    "Choose the full act plan or keep future story details hidden. Equipment challenges remain visible either way.";
                Onboarding.OnboardingSpoilersPanel.Visibility = Visibility.Visible;
                SelectOnboardingButton(
                    onboardingReveal == RouteRevealPolicy.Everything
                        ? Onboarding.OnboardingEverythingButton
                        : Onboarding.OnboardingNextThreeButton,
                    Onboarding.OnboardingEverythingButton,
                    Onboarding.OnboardingNextThreeButton);
                Onboarding.OnboardingNextButton.Content = "Continue  ›";
                break;
            case OnboardingStep.Ai:
                Onboarding.OnboardingTitleText.Text = "Choose Your Oracle";
                Onboarding.OnboardingBodyText.Text =
                    "AI is optional. Use the bundled guide alone or connect OpenRouter; either choice can be changed later in Settings.";
                Onboarding.OnboardingAiPanel.Visibility = Visibility.Visible;
                UpdateOnboardingAiState();
                Onboarding.OnboardingNextButton.Content = "Continue  ›";
                break;
            case OnboardingStep.Party:
                Onboarding.OnboardingTitleText.Text = "Who Is at Your Table?";
                Onboarding.OnboardingBodyText.Text =
                    "Set who is actually in the party and their level. Fight readiness and danger warnings key off your lowest active level.";
                Onboarding.OnboardingPartyPanel.Visibility = Visibility.Visible;
                Onboarding.OnboardingPartyLevelText.Text = $"L{controller.LowestPartyLevel}";
                Onboarding.OnboardingRosterList.ItemsSource = (controller.Run.Roster ?? controller.Run.Party)
                    .OrderBy(member => member.RosterStatus)
                    .ThenBy(member => member.Name)
                    .ToList();
                Onboarding.OnboardingNextButton.Content = "Continue  ›";
                break;
            case OnboardingStep.CatchUp:
                Onboarding.OnboardingTitleText.Text = "Where Are You?";
                Onboarding.OnboardingBodyText.Text =
                    "Pick the last landmark you finished. Everything before it is marked caught up so the route resumes exactly where you are.";
                Onboarding.OnboardingCatchUpPanel.Visibility = Visibility.Visible;
                UpdateOnboardingActButtons();
                RenderOnboardingLandmarks();
                Onboarding.OnboardingNextButton.Content = "Catch Up & Continue  ›";
                break;
            case OnboardingStep.Ready:
                Onboarding.OnboardingTitleText.Text = "Ready to Adventure";
                Onboarding.OnboardingBodyText.Text =
                    "Everything is saved locally on this PC — no account, no sign-in. The bundled guide works fully offline.";
                Onboarding.OnboardingReadyPanel.Visibility = Visibility.Visible;
                Onboarding.OnboardingStartupToggle.IsChecked = SettingsScreen.StartupToggle.IsChecked;
                Onboarding.OnboardingNextButton.Content = "Start Adventuring";
                break;
        }
    }

    internal void OnOnboardingModeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is not Button { Tag: string raw } ||
            !Enum.TryParse<OnboardingMode>(raw, out var mode))
        {
            return;
        }

        onboardingMode = mode;
        onboardingSteps = OnboardingFlow.Steps(onboardingMode);
        onboardingIndex = 1;
        ShowOnboardingStep();
    }

    internal void OnOnboardingDifficultyClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            Enum.TryParse<RunDifficulty>(raw, out var difficulty))
        {
            onboardingDifficulty = difficulty;
            UpdateOnboardingDifficultyState();
        }
    }

    private void UpdateOnboardingDifficultyState()
    {
        var buttons = new Dictionary<RunDifficulty, Button>
        {
            [RunDifficulty.Balanced] = Onboarding.OnboardingBalancedButton,
            [RunDifficulty.Tactician] = Onboarding.OnboardingTacticianButton,
            [RunDifficulty.Honour] = Onboarding.OnboardingHonourButton,
            [RunDifficulty.Explorer] = Onboarding.OnboardingExplorerButton,
        };
        SelectOnboardingButton(
            buttons[onboardingDifficulty],
            buttons.Values.ToArray());
        var explorer = onboardingDifficulty == RunDifficulty.Explorer;
        Onboarding.OnboardingExplorerExplanation.Visibility = explorer
            ? Visibility.Visible
            : Visibility.Collapsed;
        Onboarding.OnboardingNextButton.IsEnabled = !explorer;
    }

    internal void OnCloseExplorerOverlayClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Hide();
    }

    internal void OnOnboardingSpoilerClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            Enum.TryParse<RouteRevealPolicy>(raw, out var reveal))
        {
            onboardingReveal = reveal;
            SelectOnboardingButton(
                reveal == RouteRevealPolicy.Everything
                    ? Onboarding.OnboardingEverythingButton
                    : Onboarding.OnboardingNextThreeButton,
                Onboarding.OnboardingEverythingButton,
                Onboarding.OnboardingNextThreeButton);
        }
    }

    internal void OnOnboardingAiChoiceClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        onboardingUseOpenRouter = sender is Button { Tag: "OpenRouter" };
        UpdateOnboardingAiState();
    }

    private void UpdateOnboardingAiState()
    {
        SelectOnboardingButton(
            onboardingUseOpenRouter
                ? Onboarding.OnboardingOpenRouterButton
                : Onboarding.OnboardingGuideOnlyButton,
            Onboarding.OnboardingGuideOnlyButton,
            Onboarding.OnboardingOpenRouterButton);
        Onboarding.OnboardingKeyPanel.Visibility = onboardingUseOpenRouter
            ? Visibility.Visible
            : Visibility.Collapsed;
        Onboarding.OnboardingKeyStatusText.Text = openRouterKeyConfigured
            ? "API key saved in Windows Credential Manager."
            : "Enter an OpenRouter API key or continue and add it later in Settings.";
        Onboarding.OnboardingKeyPasswordBox.Visibility = openRouterKeyConfigured
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    internal void OnSaveOnboardingKeyClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var key = Onboarding.OnboardingKeyPasswordBox.Password.Trim();
        if (key.Length == 0)
        {
            Onboarding.OnboardingKeyStatusText.Text = "Enter an OpenRouter API key first.";
            return;
        }

        try
        {
            credentialStore.Save(key);
            openRouterKeyConfigured = true;
            Onboarding.OnboardingKeyPasswordBox.Clear();
            SettingsScreen.OpenRouterKeyStatusText.Text =
                "Key saved for this Windows user in Windows Credential Manager.";
            UpdateOpenRouterPanels();
            UpdateNetworkButtons();
            UpdateOnboardingAiState();
        }
        catch (Exception exception)
        {
            Onboarding.OnboardingKeyStatusText.Text =
                $"Windows Credential Manager could not save the key: {exception.Message}";
        }
    }

    internal async void OnOnboardingLevelDownClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.SetAllPartyLevelsAsync(controller.LowestPartyLevel - 1);
        ShowOnboardingStep();
    }

    internal async void OnOnboardingLevelUpClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.SetAllPartyLevelsAsync(controller.LowestPartyLevel + 1);
        ShowOnboardingStep();
    }

    internal async void OnOnboardingRosterStatusChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is not ComboBox
            {
                Tag: string memberId,
                SelectedItem: ComboBoxItem { Tag: RosterStatus status },
            })
        {
            return;
        }

        var member = (controller.Run.Roster ?? controller.Run.Party)
            .FirstOrDefault(candidate => candidate.Id == memberId);
        if (member is null || member.RosterStatus == status)
        {
            return;
        }

        if (!await controller.SetRosterStatusAsync(memberId, status))
        {
            ShowError(status == RosterStatus.Active
                ? "The active party already has four members."
                : $"Could not change {member.Name}'s roster status.");
        }

        ShowOnboardingStep();
    }

    internal async void OnOnboardingActClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            int.TryParse(raw, out var act) &&
            await controller.SelectOnboardingActAsync(act))
        {
            onboardingCatchUpCheckpointId = null;
            ShowOnboardingStep();
        }
    }

    private void UpdateOnboardingActButtons()
    {
        var act = controller.Run.SelectedAct ?? 1;
        SelectOnboardingButton(
            act switch
            {
                2 => Onboarding.OnboardingAct2Button,
                3 => Onboarding.OnboardingAct3Button,
                _ => Onboarding.OnboardingAct1Button,
            },
            Onboarding.OnboardingAct1Button,
            Onboarding.OnboardingAct2Button,
            Onboarding.OnboardingAct3Button);
    }

    private void RenderOnboardingLandmarks()
    {
        var rows = new List<OnboardingLandmarkRow>
        {
            new(null, "Start of the act", "Nothing to mark"),
        };
        rows.AddRange(
            controller.Route
                .OrderBy(checkpoint => checkpoint.RouteOrder)
                .Select(
                    checkpoint => new OnboardingLandmarkRow(
                        checkpoint.Id,
                        checkpoint.Name,
                        checkpoint.Area)));
        Onboarding.OnboardingLandmarkList.ItemsSource = rows;
        Onboarding.OnboardingLandmarkList.SelectedItem =
            rows.FirstOrDefault(row => row.CheckpointId == onboardingCatchUpCheckpointId) ??
            rows[0];
        UpdateOnboardingCatchUpCaption();
    }

    internal void OnOnboardingLandmarkChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (Onboarding.OnboardingLandmarkList.SelectedItem is OnboardingLandmarkRow row)
        {
            onboardingCatchUpCheckpointId = row.CheckpointId;
            UpdateOnboardingCatchUpCaption();
        }
    }

    private void UpdateOnboardingCatchUpCaption()
    {
        var act = controller.Run.SelectedAct ?? 1;
        if (onboardingCatchUpCheckpointId is not { } checkpointId)
        {
            Onboarding.OnboardingCatchUpCaptionText.Text =
                $"◆  Starting Act {act} from the beginning — nothing is marked.";
            return;
        }

        var landmark = controller.Walkthrough.FirstOrDefault(
            step => step.CheckpointId == checkpointId);
        var progress = controller.Run.WalkthroughProgress ?? [];
        var count = landmark is null
            ? 0
            : controller.Walkthrough.Count(
                step => step.Order <= landmark.Order &&
                        !progress.ContainsKey(step.Id));
        Onboarding.OnboardingCatchUpCaptionText.Text =
            $"◆  {count} earlier step{(count == 1 ? string.Empty : "s")} will be marked caught up — distinct from steps completed with the assistant.";
    }

    private void SelectOnboardingButton(
        Button selected,
        params Button[] buttons)
    {
        foreach (var button in buttons)
        {
            var active = button == selected;
            button.Background = active
                ? FindResource("BG3ProminentActionBrush") as Brush
                : FindResource("BG3ActionBrush") as Brush;
            button.BorderBrush = active
                ? FindResource("BG3GoldBrush") as Brush
                : FindResource("BG3ActionBorderBrush") as Brush;
        }
    }

    internal void OnOnboardingBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (onboardingIndex > 0)
        {
            onboardingIndex--;
            ShowOnboardingStep();
        }
    }

    internal async void OnOnboardingNextClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var step = onboardingSteps[onboardingIndex];
        if (!OnboardingFlow.AllowsAdvance(step, onboardingDifficulty))
        {
            return;
        }

        if (step == OnboardingStep.CatchUp &&
            onboardingCatchUpCheckpointId is { } checkpointId)
        {
            controller.Run.WalkthroughProgress = CatchUp.Ledger(
                    checkpointId,
                    controller.Walkthrough,
                    controller.Run.WalkthroughProgress ?? new())
                ?.ToDictionary(pair => pair.Key, pair => pair.Value);
        }

        if (onboardingIndex < onboardingSteps.Count - 1)
        {
            onboardingIndex++;
            ShowOnboardingStep();
            return;
        }

        controller.Run.Difficulty = onboardingDifficulty;
        controller.Run.RouteRevealPolicy = onboardingReveal;
        await controller.SaveAsync();
        if (Onboarding.OnboardingStartupToggle.IsChecked == true)
        {
            ApplyStartupStatus(await startup.RequestEnableFromUserActionAsync());
        }

        await controller.UpdatePreferencesAsync(
            controller.Preferences with
            {
                OnboardingVersion = OnboardingFlow.Version,
            });
        Onboarding.OnboardingPanel.Visibility = Visibility.Collapsed;
        UpdatePlannerShell();
        RefreshView();
        overlay.ShowPreview();
        Hide();
    }
}
