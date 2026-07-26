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
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    internal void OnNowMoreChanged(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PlannerTabs.SelectedIndex == 0)
        {
            UpdatePlannerShell();
        }
    }

    internal async void OnCompleteCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await CompleteCurrentTaskAsync();
    }

    private async Task CompleteCurrentTaskAsync()
    {
        if (controller.CurrentStep?.Decision is not null)
        {
            PlannerTabs.SelectedIndex = 1;
            RouteScreen.RouteList.SelectedItem = controller.CurrentStep;
            RouteScreen.RouteStepOutcomeText.Text =
                "Choose the reviewed outcome below before marking this step done.";
            return;
        }

        await controller.CompleteCurrentGoalAsync();
    }

    private void OnOverlayOpenRouteRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        (Application.Current as App)?.ShowMainWindow();
        ShowRoute();
    }

    private void OnOverlayOpenChatRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        (Application.Current as App)?.ShowMainWindow();
        ShowChat();
    }

    private async void OnOverlayTaskDoneRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await CompleteCurrentTaskAsync();
    }

    private void OnOverlaySnoozeRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        controller.SnoozeWarnings();
    }

    private async void OnOverlayMuteRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ToggleMuteCurrentAsync();
    }

    private void OnOverlayPinRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (controller.CombatCardPinned)
        {
            controller.UnpinFight();
        }
        else if (!controller.PinCurrentFight())
        {
            ShowError("Resolve readiness blockers before pinning this fight.");
        }
    }

    internal async void OnSkipCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await ApplyDispositionWithConfirmationAsync(CheckpointDisposition.Skipped);
    }

    internal async void OnRevisitCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
    }

    internal async void OnFollowRouteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.FollowRecommendationAsync();
    }

    internal async void OnMuteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ToggleMuteCurrentAsync();
    }

    internal async void OnClearTargetClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ClearGearTargetAsync();
    }

    internal void OnPinFightClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (controller.CombatCardPinned)
        {
            controller.UnpinFight();
            return;
        }

        if (!controller.PinCurrentFight())
        {
            ShowError("Resolve readiness blockers before pinning this fight.");
        }
    }

    internal void OnSnoozeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        controller.SnoozeWarnings();
    }
    private void RefreshNowScreen()
    {
        var goal = controller.GoalPresentation;
        NowScreen.GoalTitleText.Text = goal.Title;
        NowScreen.GoalMetaText.Text = string.IsNullOrEmpty(goal.Area)
            ? $"Act {controller.Run.SelectedAct ?? 1}"
            : goal.Area;
        NowScreen.GoalLevelChipText.Text = $"L{goal.MinimumLevel}+";
        NowScreen.GoalDangerChipText.Text = $"{goal.Danger} risk";
        NowScreen.GoalDangerChipText.Foreground =
            goal.Danger.ToLowerInvariant() switch
            {
                "extreme" => FindResource("BG3DangerBrush") as Brush,
                "high" => FindResource("BG3WarningBrush") as Brush,
                "medium" => FindResource("BG3CautionBrush") as Brush,
                _ => FindResource("BG3ControlBrush") as Brush,
            };
        NowScreen.GoalContextChipText.Text = controller.CurrentStep is { } currentStep
            ? StepEncounterRules.Classify(currentStep).Label()
            : controller.CurrentCheckpoint is not null
                ? "FIGHT"
                : controller.TargetContext is not null
                    ? "EQUIPMENT"
                    : "ROUTE";
        NowScreen.GoalDoText.Text = controller.TargetContext is { } target
            ? target.Gear.Acquisition
            : controller.CurrentStep?.Summary ??
              controller.CurrentCheckpoint?.Advice ??
              goal.Title;
        NowScreen.GoalAvoidText.Text = goal.Avoid;
        NowScreen.GoalWhyText.Text = controller.TargetContext?.Gear.Why ??
                           controller.CurrentStep?.Why ??
                           controller.CurrentCheckpoint?.Notes.FirstOrDefault() ??
                           "Follow the reviewed route before moving on.";
        var readiness = controller.Readiness;
        NowScreen.ReadinessText.Text = readiness is null
            ? "No fight gate is attached to this activity."
            : $"{readiness.Status.ToUpperInvariant()} · " +
              (readiness.Blockers.FirstOrDefault() ??
               readiness.Warnings.FirstOrDefault() ??
               readiness.NextActions.FirstOrDefault() ??
               "Ready.");
        if (controller.WarningsSuppressed && readiness is not null)
        {
            NowScreen.ReadinessText.Text += " · warnings suppressed";
        }
        var checkpoint = controller.CurrentCheckpoint;
        NowScreen.MuteButton.Content = checkpoint is not null &&
                             controller.Run.MutedCheckpointIds?.Contains(checkpoint.Id) == true
            ? "Unmute warnings"
            : "Mute warnings";
        NowScreen.ClearTargetButton.Visibility = controller.TargetContext is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        NowScreen.PinFightButton.Content = controller.CombatCardPinned
            ? "Unpin fight"
            : "Pin fight";
    }

}
