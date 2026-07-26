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
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    internal void OnRouteSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing)
        {
            return;
        }

        if (RouteScreen.RouteList.SelectedItem is not RoutePlannerRow row)
        {
            RouteScreen.RouteStepTitleText.Text = string.Empty;
            RouteScreen.RouteStepMetaText.Text = string.Empty;
            RouteScreen.RouteStepSummaryText.Text = string.Empty;
            RouteScreen.RouteStepAvoidText.Text = string.Empty;
            RouteScreen.RouteStepWhyText.Text = string.Empty;
            return;
        }

        if (row.Pickup is { } pickup)
        {
            ShowRouteGear(pickup);
            ShowRouteDetailPage();
            return;
        }

        if (row.Step is not { } step)
        {
            return;
        }

        RouteScreen.RouteStepPanel.Visibility = Visibility.Visible;
        RouteScreen.RouteGearPanel.Visibility = Visibility.Collapsed;
        routeDetailStepId = step.Id;
        routeDetailPickup = null;
        RouteScreen.RouteStepTitleText.Text = step.Title;
        RouteScreen.RouteStepMetaText.Text =
            $"{step.Phase} · L{step.MinimumLevel}+ · {StepEncounterRules.Classify(step).Label()}";
        RouteScreen.RouteStepSummaryText.Text = step.Summary;
        RouteScreen.RouteStepAvoidText.Text = string.IsNullOrEmpty(step.Avoid)
            ? string.Empty
            : $"Avoid: {step.Avoid}";
        RouteScreen.RouteStepWhyText.Text = step.Why;
        RouteScreen.RouteStepRewardsText.Text = step.Rewards.Count == 0
            ? string.Empty
            : $"Rewards: {string.Join(" - ", step.Rewards)}";
        var prerequisites = step.Prerequisites
            .Concat(step.Dependencies.Select(dependency => dependency.StepId))
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(
                value =>
                    controller.Walkthrough.FirstOrDefault(candidate => candidate.Id == value)
                        ?.Title ?? value)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        RouteScreen.RouteStepPrerequisitesText.Text = prerequisites.Count == 0
            ? string.Empty
            : $"First: {string.Join(" - ", prerequisites)}";
        RouteScreen.RouteStepCompletionText.Text = step.CompletionChecks.Count == 0
            ? string.Empty
            : $"Done when: {string.Join(" - ", step.CompletionChecks)}";
        var recordedOutcome =
            controller.Run.WalkthroughOutcomes?.GetValueOrDefault(step.Id);
        RouteScreen.RouteStepOutcomeText.Text = recordedOutcome is null
            ? string.Empty
            : $"Recorded outcome: {recordedOutcome}";
        RouteScreen.RouteDecisionGroup.Visibility =
            step.Decision is null ? Visibility.Collapsed : Visibility.Visible;
        if (step.Decision is { } decision)
        {
            var options = new[] { decision.Recommended }
                .Concat(decision.Alternatives)
                .ToList();
            RouteScreen.RouteDecisionText.Text =
                $"{decision.Prompt}\n\n" +
                string.Join(
                    "\n\n",
                    options.Select(
                        option =>
                            $"{option.Label}\n" +
                            $"Benefits: {string.Join("; ", option.Benefits)}\n" +
                            $"Costs: {string.Join("; ", option.Costs)}"));
            RouteScreen.RouteOutcomePicker.ItemsSource = options;
            RouteScreen.RouteOutcomePicker.SelectedItem =
                options.FirstOrDefault(option => option.Label == recordedOutcome) ??
                options.FirstOrDefault();
        }
        else
        {
            RouteScreen.RouteDecisionText.Text = string.Empty;
            RouteScreen.RouteOutcomePicker.ItemsSource = null;
        }

        var incident = RunProgressRules.IncidentProtocol(step, controller.Route);
        RouteScreen.RouteIncidentGroup.Visibility =
            incident is null ? Visibility.Collapsed : Visibility.Visible;
        RouteScreen.RouteIncidentText.Text = incident is null
            ? string.Empty
            : $"Trigger: {incident.Trigger}\n" +
              $"Safe actions: {string.Join("; ", incident.SafeActions)}\n" +
              $"Never: {incident.Never}\n" +
              $"Escape: {incident.Escape}\n" +
              $"Honor change: {incident.HonorDelta}";
        RouteScreen.RouteRiskGroup.Visibility =
            step.RiskReward is null ? Visibility.Collapsed : Visibility.Visible;
        RouteScreen.RouteRiskText.Text = step.RiskReward is null
            ? string.Empty
            : $"Reward: {step.RiskReward.Reward}\n" +
              $"Risk: {step.RiskReward.Risk}\n" +
              $"Skip cost: {step.RiskReward.SkipCost}\n" +
              $"Return by: {step.RiskReward.ReturnBy}";
        RouteScreen.RouteSourceButton.IsEnabled =
            GameLauncher.TryCreateHttpUri(step.SourceUrl, out _);
        ShowRouteDetailPage();
    }

    private void ShowRouteDetailPage()
    {
        RouteScreen.RouteListColumn.Width = new GridLength(0D);
        RouteScreen.RouteDetailColumn.Width = new GridLength(1D, GridUnitType.Star);
        RouteScreen.RouteDetailScroll.ScrollToTop();
    }

    internal void OnRouteBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        RouteScreen.RouteDetailColumn.Width = new GridLength(0D);
        RouteScreen.RouteListColumn.Width = new GridLength(1D, GridUnitType.Star);
    }

    internal void OnRouteFilterButtonClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            Enum.TryParse<RouteContentFilter>(raw, out var selected))
        {
            routeFilter = selected;
            RefreshView();
        }
    }

    private void UpdateRouteFilterButtons()
    {
        var buttons = new[]
        {
            (RouteScreen.RouteAllButton, RouteContentFilter.All),
            (RouteScreen.RouteCoreButton, RouteContentFilter.Core),
            (RouteScreen.RouteEquipmentButton, RouteContentFilter.Equipment),
        };
        foreach (var (button, value) in buttons)
        {
            var selected = routeFilter == value;
            button.Background = selected
                ? FindResource("BG3ProminentActionBrush") as Brush
                : Brushes.Transparent;
            button.BorderBrush = selected
                ? FindResource("BG3ProminentActionBorderBrush") as Brush
                : Brushes.Transparent;
            button.Foreground = selected
                ? FindResource("BG3ParchmentBrush") as Brush
                : FindResource("BG3MutedParchmentBrush") as Brush;
            button.FontWeight = selected ? FontWeights.Bold : FontWeights.Normal;
        }
    }

    private void ShowRouteGear(GearPickup pickup)
    {
        RouteScreen.RouteStepPanel.Visibility = Visibility.Collapsed;
        RouteScreen.RouteGearPanel.Visibility = Visibility.Visible;
        routeDetailStepId = null;
        routeDetailPickup = pickup;
        var gear = pickup.Gear;
        RouteScreen.RouteGearTitleText.Text = gear.Item;
        RouteScreen.RouteGearMetaText.Text =
            $"For {pickup.MemberName} - {gear.Slot} - {gear.Priority} - {gear.Region}";
        RouteScreen.RouteGearEffectText.Text = string.IsNullOrWhiteSpace(gear.Effect)
            ? "No separate effect text is recorded in this guide version."
            : gear.Effect;
        RouteScreen.RouteGearAcquisitionText.Text = $"Acquire: {GearLogic.AcquireText(gear)}";
        RouteScreen.RouteGearWhyText.Text = gear.Why;
        RouteScreen.RouteGearRequirementText.Text = gear.Requirement ?? string.Empty;
    }

    internal void OnArchivedRouteSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            RouteScreen.ArchivedRouteList.SelectedItem is not ArchivedRouteRow archived)
        {
            return;
        }

        RouteScreen.RouteStepPanel.Visibility = Visibility.Visible;
        RouteScreen.RouteGearPanel.Visibility = Visibility.Collapsed;
        routeDetailStepId = archived.Step.Id;
        routeDetailPickup = null;
        RouteScreen.RouteStepTitleText.Text = archived.Step.Title;
        RouteScreen.RouteStepMetaText.Text =
            $"{archived.Disposition} - {archived.Step.Phase} - {archived.Step.Area}";
        RouteScreen.RouteStepSummaryText.Text = archived.Step.Summary;
        RouteScreen.RouteStepAvoidText.Text = archived.Step.Avoid;
        RouteScreen.RouteStepWhyText.Text = archived.Step.Why;
        RefreshRouteDetailState();
        ShowRouteDetailPage();
    }

    private void RefreshRouteDetailState()
    {
        if (routeDetailStepId is null ||
            controller.Walkthrough.FirstOrDefault(
                step => step.Id == routeDetailStepId) is not { } step)
        {
            RouteScreen.RouteDoneButton.Visibility = Visibility.Collapsed;
            RouteScreen.RouteSkipButton.Visibility = Visibility.Collapsed;
            RouteScreen.RouteRevisitButton.Visibility = Visibility.Collapsed;
            return;
        }

        var disposition = RunSafety.WalkthroughDisposition(
            step,
            controller.Run.WalkthroughProgress ??
            new Dictionary<string, CheckpointDisposition>(
                StringComparer.Ordinal));
        RouteScreen.RouteStepMetaText.Text =
            $"{StepEncounterRules.Classify(step).Label()} · " +
            $"L{step.MinimumLevel}+ · {disposition.ToString().ToUpperInvariant()} · " +
            $"{step.Phase} · {step.Area}";
        RouteScreen.RouteStepOutcomeText.Text =
            controller.Run.WalkthroughOutcomes?.GetValueOrDefault(step.Id) is
                { } outcome
                ? $"Outcome: {outcome}"
                : string.Empty;
        RouteScreen.RouteDoneButton.Visibility =
            step.Decision is null && disposition != CheckpointDisposition.Completed
                ? Visibility.Visible
                : Visibility.Collapsed;
        RouteScreen.RouteSkipButton.Visibility =
            disposition == CheckpointDisposition.Pending
                ? Visibility.Visible
                : Visibility.Collapsed;
        RouteScreen.RouteRevisitButton.Visibility =
            disposition == CheckpointDisposition.Pending
                ? Visibility.Collapsed
                : Visibility.Visible;
    }

    internal async void OnRecordOutcomeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step &&
            RouteScreen.RouteOutcomePicker.SelectedItem is DecisionOption option)
        {
            await controller.ResolveOutcomeAsync(step, option.Label);
        }
    }

    internal void OnOpenRouteSourceClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is not { } step)
        {
            return;
        }

        OpenExternalLink(step.SourceUrl, "reviewed route source");
    }

    internal async void OnTrackRouteGearClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is { } pickup)
        {
            await controller.SetGearTargetAsync(pickup.MemberId, pickup.Gear);
        }
    }

    internal async void OnMarkRouteGearObtainedClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is { } pickup)
        {
            await controller.MarkGearObtainedAsync(pickup.MemberId, pickup.Gear);
        }
    }

    internal void OnOpenRouteGearLinkClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is not { } pickup)
        {
            return;
        }

        OpenExternalLink(
            !string.IsNullOrWhiteSpace(pickup.Gear.Wiki)
                ? pickup.Gear.Wiki
                : pickup.Gear.Source,
            "item source");
    }

    private void OpenExternalLink(string? value, string label)
    {
        try
        {
            launcher.OpenExternalMap(value ?? string.Empty);
        }
        catch (Exception exception)
        {
            ShowError($"Windows could not open the {label}: {exception.Message}");
        }
    }

    internal async void OnFocusSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step)
        {
            await controller.FocusStepAsync(step);
            PlannerTabs.SelectedIndex = 0;
        }
    }

    internal async void OnCompleteSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is not { } step)
        {
            return;
        }

        await controller.FocusStepAsync(step);
        if (step.Decision is null)
        {
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Completed);
            return;
        }

        var options = new[] { step.Decision.Recommended }
            .Concat(step.Decision.Alternatives)
            .ToList();
        var outcome = options.FirstOrDefault()?.Label;
        if (outcome is not null)
        {
            ShowActionConfirmation(
                "Record route outcome?",
                $"Record the reviewed option “{outcome}”? If something else happened, keep the step open until the outcome can be selected.",
                "Record outcome",
                () => controller.ResolveOutcomeAsync(step, outcome));
        }
    }

    internal async void OnSkipSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step)
        {
            await controller.FocusStepAsync(step);
            await ApplyDispositionWithConfirmationAsync(CheckpointDisposition.Skipped);
        }
    }

    internal async void OnRevisitSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (RouteScreen.ArchivedRouteList.SelectedItem is ArchivedRouteRow archivedRow)
        {
            await controller.FocusStepAsync(archivedRow.Step);
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
        }
        else if ((RouteScreen.RouteList.SelectedItem as RoutePlannerRow)?.Step is { } step)
        {
            await controller.FocusStepAsync(step);
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
        }
    }

    private async Task ApplyDispositionWithConfirmationAsync(
        CheckpointDisposition disposition)
    {
        var request = controller.RequestDisposition(disposition);
        if (request.RequiresConfirmation)
        {
            ShowActionConfirmation(
                "Confirm route change",
                request.ConfirmationMessage ??
                "This route change may have irreversible consequences.",
                disposition == CheckpointDisposition.Skipped
                    ? "Skip this step"
                    : "Confirm",
                () => controller.SetCurrentDispositionAsync(disposition));
            return;
        }

        await controller.SetCurrentDispositionAsync(disposition);
    }
    private void RefreshRouteScreen()
    {
        var selectedRouteStepId =
            (RouteScreen.RouteList.SelectedItem as RoutePlannerRow)?.Step?.Id;
        var selectedPickupId =
            (RouteScreen.RouteList.SelectedItem as RoutePlannerRow)?.Pickup?.Id;
        var routePresentation = RoutePlannerRules.Present(
            controller.Walkthrough,
            controller.Run.WalkthroughProgress,
            controller.Run.WalkthroughOutcomes,
            controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything,
            controller.RoutePickups,
            routeFilter,
            controller.CurrentStep,
            controller.LowestPartyLevel);
        RouteScreen.RouteProgressBar.Value = routePresentation.Progress;
        RouteScreen.RouteOverlineText.Text =
            $"ROUTE · ACT {controller.Run.SelectedAct ?? 1}";
        RouteScreen.RouteProgressText.Text = $"L{controller.LowestPartyLevel}";
        RouteScreen.RouteDoneText.Text =
            $"{routePresentation.ArchivedCount}/{routePresentation.TotalCount} done";
        RouteScreen.RouteGateText.Text = (controller.Run.SelectedAct ?? 1) == 3
            ? "Final act - no next-act gate."
            : controller.CurrentActConsequences.Count == 0
                ? $"Act {(controller.Run.SelectedAct ?? 1) + 1} gate: ready."
                : $"Act {(controller.Run.SelectedAct ?? 1) + 1} gate: " +
                  $"{controller.CurrentActConsequences.Count} consequence" +
                  (controller.CurrentActConsequences.Count == 1 ? string.Empty : "s") +
                  " remain.";
        RouteScreen.RouteSpoilerText.Text = routePresentation.SpoilerLight
            ? "Spoiler-light - showing only the next 3 route tasks."
            : string.Empty;
        RouteScreen.RouteDeadlineList.ItemsSource = controller.Payload.TimedEvents;
        RouteScreen.RouteDeadlinesExpander.Visibility =
            controller.Payload.TimedEvents.Count == 0
                ? Visibility.Collapsed
                : Visibility.Visible;
        RouteScreen.RouteList.ItemsSource = routePresentation.Rows;
        RouteScreen.ArchivedRouteList.ItemsSource = routePresentation.Archived;
        RouteScreen.RouteList.SelectedItem = routePresentation.Rows.FirstOrDefault(
                                     row => row.Step?.Id == selectedRouteStepId) ??
                                 routePresentation.Rows.FirstOrDefault(
                                     row => row.Pickup?.Id == selectedPickupId) ??
                                 routePresentation.Rows.FirstOrDefault(
                                     row => row.Step?.Id == controller.CurrentStep?.Id) ??
                                 routePresentation.Rows.FirstOrDefault(
                                 row => row.IsSelectable);
        RouteScreen.ArchivedRouteList.SelectedItem =
            routePresentation.Archived.FirstOrDefault(
                row => row.Step.Id == routeDetailStepId);
        UpdateRouteFilterButtons();
        RefreshRouteDetailState();
    }

}
