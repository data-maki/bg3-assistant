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
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    private void RenderActLedger()
    {
        var activeAct = controller.Run.SelectedAct ?? 1;
        if (actAcceptanceRunId != controller.Run.Id ||
            actAcceptanceAct != activeAct)
        {
            actAcceptanceRunId = controller.Run.Id;
            actAcceptanceAct = activeAct;
            acceptsActRouteConsequences = false;
        }

        if (viewedAct is < 1 or > 3)
        {
            viewedAct = activeAct;
        }

        var summary = controller.Payload.Acts.FirstOrDefault(
            candidate => candidate.Act == viewedAct);
        var locked = controller.Run.ActLedgerIsLocked(viewedAct);
        var active = viewedAct == activeAct;
        var gear = controller.ActGear(viewedAct);
        var reviewed = gear.Where(
                item =>
                    ActTransitionRules.ReviewStatus(
                        controller.Run,
                        item,
                        viewedAct) is not null)
            .ToList();
        var pending = gear.Where(
                item =>
                    ActTransitionRules.ReviewStatus(
                        controller.Run,
                        item,
                        viewedAct) is null)
            .Select(item => new ActGearRow(item, !locked))
            .ToList();

        ActScreen.ActLedgerStatusText.Text = active
            ? "ACTIVE RUN"
            : locked ? "LOCKED HISTORY" : "PREVIEW";
        ActScreen.ActLedgerStatusText.Foreground = active
            ? FindResource("BG3SuccessBrush") as Brush
            : FindResource("BG3MutedParchmentBrush") as Brush;
        var ledgerButtons = new[]
        {
            ActScreen.Act1LedgerButton,
            ActScreen.Act2LedgerButton,
            ActScreen.Act3LedgerButton,
        };
        foreach (var button in ledgerButtons)
        {
            var selected = Equals(button.Tag?.ToString(), viewedAct.ToString());
            button.Background = selected
                ? FindResource("BG3ActionBorderBrush") as Brush
                : FindResource("BG3ActionBrush") as Brush;
            button.BorderBrush = selected
                ? FindResource("BG3MutedParchmentBrush") as Brush
                : FindResource("BG3ActionBorderBrush") as Brush;
            button.FontWeight = selected ? FontWeights.Bold : FontWeights.Normal;
        }

        ActScreen.ActNumberText.Text = $"ACT {viewedAct}";
        ActScreen.ActEquipmentCountText.Text =
            $"{summary?.EquipmentCount ?? 0} equipment rows";
        ActScreen.ActTitleText.Text = summary?.Title ?? "Guide data unavailable";
        ActScreen.ActAvailabilityText.Text = summary?.RouteAvailable == true
            ? "Route available"
            : "Route pending";
        ActScreen.ActRouteStatusIcon.Text = summary?.RouteAvailable == true ? "●" : "○";
        ActScreen.ActMapNameText.Text = summary?.MapName ?? $"Act {viewedAct}";
        ActScreen.ActReviewCountText.Text = $"{reviewed.Count}/{gear.Count}";
        ActScreen.ActReviewHelpText.Text = locked
            ? "This completed act's equipment decisions are read-only."
            : active
                ? "Confirm the relevant items for the active party before leaving this act."
                : "Preview and review this act's equipment without advancing the run.";
        ActScreen.ActPendingGearList.ItemsSource = pending;
        ActScreen.ActEmptyReviewText.Visibility = pending.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActScreen.ActEmptyReviewText.Text = gear.Count == 0
            ? "Assign reviewed builds on Party to create an equipment checklist."
            : "All equipment reviewed.";
        ActScreen.ActReviewedSummaryText.Visibility = reviewed.Count == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        ActScreen.ActReviewedSummaryText.Text = $"●  Reviewed ({reviewed.Count})";

        var consequences = active
            ? controller.CurrentActConsequences
            : Array.Empty<string>();
        ActScreen.ActConsequencesPanel.Visibility = active && consequences.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActScreen.ActConsequencesTitleText.Text =
            $"UNRESOLVED CONSEQUENCES · {consequences.Count}";
        ActScreen.ActConsequencesList.ItemsSource = consequences.Take(4);
        ActScreen.ActAcceptConsequencesCheckBox.Content =
            $"I accept these unresolved Act {activeAct} consequences";
        ActScreen.ActAcceptConsequencesCheckBox.IsChecked =
            acceptsActRouteConsequences;

        ActScreen.ActBrowsingPanel.Visibility = active
            ? Visibility.Collapsed
            : Visibility.Visible;
        ActScreen.ActTransitionPanel.Visibility = active
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActScreen.ActBrowsingTitleText.Text = locked
            ? $"🔒  Act {viewedAct} ledger is locked"
            : $"◉  Previewing Act {viewedAct}";
        ActScreen.ActBrowsingBodyText.Text = locked
            ? "This review remains available as history, but it was locked when the run advanced."
            : $"Your run remains in Act {activeAct}. Reviewing this equipment does not advance the run or close the active ledger.";
        ActScreen.ReturnActiveActButton.Content = $"Return to active Act {activeAct}";

        if (!active)
        {
            return;
        }

        var completed = activeAct == 3 && controller.Run.FinalActRecord is not null;
        var blocker = activeAct == 3
            ? controller.FinalActBlockedReason
            : controller.ActTransitionBlockedReason;
        ActScreen.ActGateText.Text = completed
            ? "Run complete · Act 3 ledger locked."
            : blocker ??
              (controller.CurrentActConsequences.Count > 0
                  ? string.Join("\n", controller.CurrentActConsequences)
                  : "The equipment review is complete. Advancing permanently locks this act ledger.");
        ActScreen.AdvanceActButton.Visibility = completed
            ? Visibility.Collapsed
            : Visibility.Visible;
        ActScreen.AdvanceActButton.IsEnabled =
            blocker is null &&
            (consequences.Count == 0 || acceptsActRouteConsequences);
        ActScreen.AdvanceActButton.Content = activeAct == 3
            ? "Complete run"
            : $"Advance to Act {activeAct + 1}";
    }

    internal async void OnActGearObtainedClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { DataContext: ActGearRow row })
        {
            await controller.SetActGearReviewAsync(
                row.Gear,
                viewedAct,
                ActGearReviewStatus.Obtained);
        }
    }

    internal async void OnActGearMissedClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { DataContext: ActGearRow row })
        {
            await controller.SetActGearReviewAsync(
                row.Gear,
                viewedAct,
                ActGearReviewStatus.Missed);
        }
    }

    internal void OnActLedgerClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string actText } &&
            int.TryParse(actText, out var act))
        {
            viewedAct = act;
            RenderActLedger();
        }
    }

    internal void OnReturnActiveActClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        viewedAct = controller.Run.SelectedAct ?? 1;
        RenderActLedger();
    }

    internal void OnActAcceptanceChanged(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing)
        {
            return;
        }

        acceptsActRouteConsequences =
            ActScreen.ActAcceptConsequencesCheckBox.IsChecked == true;
        RenderActLedger();
    }

    internal void OnAdvanceActClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var consequences = controller.CurrentActConsequences;
        var currentAct = controller.Run.SelectedAct ?? 1;
        ShowActionConfirmation(
            currentAct == 3
                ? "Complete this run?"
                : $"Leave Act {currentAct} permanently?",
            currentAct == 3
                ? "The final route and equipment ledger will become read-only."
                : "The equipment review and unresolved consequences will be " +
                  $"locked. This run cannot return to Act {currentAct}.",
            currentAct == 3
                ? "Complete and lock Act 3"
                : $"Advance to Act {currentAct + 1}",
            () => CompleteActTransitionAsync(
                currentAct,
                consequences.Count > 0 && acceptsActRouteConsequences));
    }

    private async Task CompleteActTransitionAsync(
        int currentAct,
        bool acceptingRouteConsequences)
    {
        var succeeded = currentAct == 3
            ? await controller.FinalizeActThreeAsync(acceptingRouteConsequences)
            : await controller.AdvanceActAsync(acceptingRouteConsequences);
        if (!succeeded)
        {
            ShowError(
                (currentAct == 3
                    ? controller.FinalActBlockedReason
                    : controller.ActTransitionBlockedReason) ??
                "The act could not be advanced.");

            return;
        }

        acceptsActRouteConsequences = false;
        viewedAct = controller.Run.SelectedAct ?? 1;
        PlannerTabs.SelectedIndex = 4;
    }

    private void OnOpenActMapClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        OpenCurrentActMap();
    }
}
