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
    internal void OnPartyMemberSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            PartyScreen.Landing.PartyGrid.SelectedItem is not PartyMember member)
        {
            return;
        }

        selectedPartyMemberId = member.Id;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Visible;
        RenderPartyMemberDetail();
        PartyScreen.PartyGuidanceColumn.Width = new GridLength(0D);
        PartyScreen.PartyDetailColumn.Width = new GridLength(1D, GridUnitType.Star);
    }

    private void RenderPartyMemberDetail()
    {
        if (selectedPartyMemberId is null ||
            (controller.Run.Roster ?? controller.Run.Party).FirstOrDefault(
                member => member.Id == selectedPartyMemberId) is not { } member)
        {
            return;
        }

        var build = controller.Builds.FirstOrDefault(
            candidate => candidate.Id == member.BuildId);
        PartyScreen.Member.PartyDetailNameText.Text = member.Name;
        PartyScreen.Member.PartyDetailIdentityText.Text =
            member.ManualBuild?.Name ??
            build?.Name ??
            member.ClassName ??
            "No build";
        PartyScreen.Member.PartyDetailStatusText.Text = member.RosterStatus == RosterStatus.Unrecruited
            ? "Not recruited"
            : member.RosterStatus.ToString();
        PartyScreen.Member.PartyLevelPicker.ItemsSource = Enumerable.Range(1, 12);
        PartyScreen.Member.PartyLevelPicker.SelectedItem = member.Level;
        var scores = member.EffectiveAbilityScores;
        PartyScreen.Member.PartyAbilitySummaryText.Text =
            $"STR {scores.Strength}   DEX {scores.Dexterity}   " +
            $"CON {scores.Constitution}   INT {scores.Intelligence}   " +
            $"WIS {scores.Wisdom}   CHA {scores.Charisma}";

        var step = build?.Levels.LastOrDefault(level => level.Level <= member.Level);
        PartyScreen.Member.PartyGuidanceStatusText.Text = step is null
            ? member.ManualBuild is null
                ? "NO BUILD ASSIGNED"
                : "MANUAL BUILD ACTIVE"
            : step.Level == member.Level
                ? $"NOW L{step.Level}"
                : $"LATEST PLAN L{step.Level}";
        PartyScreen.Member.PartyGuidanceTakeText.Text = step?.Take ??
                                    (member.ManualBuild is null
                                        ? "Choose, import, or create a build below."
                                        : "Open the manual builder for this level's choices.");
        PartyScreen.Member.PartyGuidanceChoicesText.Text =
            step is null || string.IsNullOrWhiteSpace(step.Choices) ||
            step.Choices == "-"
                ? string.Empty
                : $"→ {step.Choices}";
        PartyScreen.Member.PartyGuidanceTacticsText.Text =
            step is null || string.IsNullOrWhiteSpace(step.Tactics) ||
            step.Tactics == "-"
                ? string.Empty
                : $"★ {step.Tactics}";

        var buildChoices = new[] { new BuildPickerRow(null, "No reviewed build") }
            .Concat(
                controller.Builds.Select(
                    candidate => new BuildPickerRow(candidate.Id, candidate.Name)))
            .ToList();
        PartyScreen.Member.PartyBuildPicker.ItemsSource = buildChoices;
        PartyScreen.Member.PartyBuildPicker.SelectedItem =
            buildChoices.FirstOrDefault(choice => choice.BuildId == member.BuildId) ??
            buildChoices[0];
        PartyScreen.Member.PartyBuildComparisonList.ItemsSource = controller.Builds;
        PartyScreen.Member.PartyBuildComparisonList.SelectedItem = build;
    }

    internal void OnPartyBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PartyScreen.Landing.PartyGrid.SelectedItem = null;
        PartyScreen.PartyDetailColumn.Width = new GridLength(0D);
        PartyScreen.PartyGuidanceColumn.Width = new GridLength(1D, GridUnitType.Star);
        PartyScreen.BuildImport.PartyBuildImportPopover.Visibility = Visibility.Collapsed;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Visible;
    }

    internal void OnManagePartyClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Visible;
        PartyScreen.PartyGuidanceColumn.Width = new GridLength(0D);
        PartyScreen.PartyDetailColumn.Width = new GridLength(1D, GridUnitType.Star);
    }

    internal async void OnPartyLevelChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            selectedPartyMemberId is null ||
            PartyScreen.Member.PartyLevelPicker.SelectedItem is not int level)
        {
            return;
        }

        await controller.SetPartyLevelAsync(selectedPartyMemberId, level);
    }

    internal async void OnPartyBuildChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing || selectedPartyMemberId is null)
        {
            return;
        }

        var member = (controller.Run.Roster ?? controller.Run.Party)
            .FirstOrDefault(candidate => candidate.Id == selectedPartyMemberId);
        var selected = PartyScreen.Member.PartyBuildPicker.SelectedItem as BuildPickerRow;
        if (member is null || selected is null || member.BuildId == selected.BuildId)
        {
            return;
        }

        if (member.BuildId is not null)
        {
            ShowActionConfirmation(
                $"Replace {member.Name}'s build?",
                "Permanent rewards stay. Temporary effects and build-specific setup confirmation will be cleared.",
                "Replace build",
                async () =>
                {
                    var previousPlan = controller.Run.GetPartyPlan();
                    if (await controller.AssignBuildAsync(member.Id, selected.BuildId))
                    {
                        RecordPartyUndo($"Changed {member.Name}'s build", previousPlan);
                    }
                },
                RefreshView);
            return;
        }

        var previous = controller.Run.GetPartyPlan();
        if (await controller.AssignBuildAsync(member.Id, selected.BuildId))
        {
            RecordPartyUndo($"Changed {member.Name}'s build", previous);
        }
    }

    internal void OnCompareBuildsClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var show = PartyScreen.Member.PartyBuildComparisonList.Visibility != Visibility.Visible;
        PartyScreen.Member.PartyBuildComparisonList.Visibility =
            show ? Visibility.Visible : Visibility.Collapsed;
        PartyScreen.Member.CompareBuildsButton.Content =
            show ? "Hide comparison" : "Compare builds";
    }

    internal async void OnPartyBuildComparisonChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            selectedPartyMemberId is null ||
            PartyScreen.Member.PartyBuildComparisonList.SelectedItem is not BuildSummary selected)
        {
            return;
        }

        PartyScreen.Member.PartyBuildPicker.SelectedItem =
            PartyScreen.Member.PartyBuildPicker.Items
                .OfType<BuildPickerRow>()
                .FirstOrDefault(choice => choice.BuildId == selected.Id);
        await Task.CompletedTask;
    }

    internal void OnOpenBuildImportClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        buildImportAssignMemberId = selectedPartyMemberId;
        PartyScreen.BuildImport.PartyBuildImportStatusText.Text = string.Empty;
        PartyScreen.BuildImport.PartyBuildImportPopover.Visibility = Visibility.Visible;
        PartyScreen.BuildImport.PartyBuildImportUrlTextBox.Focus();
    }

    internal void OnClosePartyBuildImportClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (importCancellation is not null)
        {
            PartyScreen.BuildImport.PartyBuildImportStatusText.Text =
                "Cancelling build import…";
            importOperationVersion++;
            importCancellation.Cancel();
            return;
        }

        PartyScreen.BuildImport.PartyBuildImportPopover.Visibility = Visibility.Collapsed;
        buildImportAssignMemberId = null;
    }

    internal async void OnPartyImportBuildClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (importCancellation is not null)
        {
            PartyScreen.BuildImport.PartyBuildImportStatusText.Text =
                "Cancelling build import…";
            importOperationVersion++;
            importCancellation.Cancel();
            return;
        }

        if (await ImportBuildFromUrlAsync(
                PartyScreen.BuildImport.PartyBuildImportUrlTextBox.Text.Trim(),
                buildImportAssignMemberId,
                message => PartyScreen.BuildImport.PartyBuildImportStatusText.Text = message))
        {
            PartyScreen.BuildImport.PartyBuildImportUrlTextBox.Clear();
        }
    }

    internal void OnPartyAbilitiesClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Collapsed;
        PartyScreen.ManualBuild.ManualBuildPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Abilities.PartyAbilityPanel.Visibility = Visibility.Visible;
        selectedAbilitySetupId = null;
        RenderPartyAbilityPage();
    }

    internal async void OnManualBuildClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedPartyMemberId is null ||
            !await controller.BeginManualBuildAsync(selectedPartyMemberId))
        {
            return;
        }

        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Abilities.PartyAbilityPanel.Visibility = Visibility.Collapsed;
        PartyScreen.ManualBuild.ManualBuildPanel.Visibility = Visibility.Visible;
        selectedManualLevel = Math.Clamp(
            (controller.Run.Roster ?? controller.Run.Party)
                .First(member => member.Id == selectedPartyMemberId).Level,
            1,
            12);
        RenderManualBuildPage();
    }

    internal void OnPartyCharacterBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PartyScreen.Abilities.PartyAbilityPanel.Visibility = Visibility.Collapsed;
        PartyScreen.ManualBuild.ManualBuildPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Roster.PartyRosterPanel.Visibility = Visibility.Collapsed;
        PartyScreen.Member.PartyMemberDetailPanel.Visibility = Visibility.Visible;
        RenderPartyMemberDetail();
    }

    internal void OnResetCharacterClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedPartyMember() is not { } member)
        {
            return;
        }

        Dialogs.ResetCharacterConfirmationTitleText.Text =
            $"Reset {member.Name}'s character plan?";
        Dialogs.ResetCharacterConfirmationOverlay.Visibility = Visibility.Visible;
    }

    internal void OnCancelResetCharacterClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dialogs.ResetCharacterConfirmationOverlay.Visibility = Visibility.Collapsed;
    }

    internal async void OnConfirmResetCharacterClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedPartyMemberId is null)
        {
            return;
        }

        var member = SelectedPartyMember();
        var previousPlan = controller.Run.GetPartyPlan();
        if (await controller.ResetCharacterPlanAsync(selectedPartyMemberId) &&
            member is not null)
        {
            RecordPartyUndo($"Reset {member.Name}'s character plan", previousPlan);
        }
        Dialogs.ResetCharacterConfirmationOverlay.Visibility = Visibility.Collapsed;
        OnPartyBackClick(this, new RoutedEventArgs());
    }

    private void RefreshPartyScreen()
    {
        var roster = controller.Run.Roster ?? controller.Run.Party;
        if (partyUndoRunId != controller.Run.Id)
        {
            ClearPartyUndo();
        }
        PartyScreen.Landing.PartyGrid.ItemsSource = controller.ActiveParty;
        PartyScreen.Landing.PartyActiveCountText.Text = $"{controller.ActiveParty.Count}/4 active";
        PartyScreen.Roster.PartyRosterActiveCountText.Text =
            $"{controller.ActiveParty.Count}/4 active";
        PartyScreen.Roster.PartyRosterList.ItemsSource = roster
            .OrderBy(member => member.RosterStatus switch
            {
                RosterStatus.Active => 0,
                RosterStatus.Camp => 1,
                RosterStatus.Unrecruited => 2,
                _ => 3,
            })
            .ThenBy(member => member.Name)
            .ToList();
        var active = roster.Where(member => member.RosterStatus == RosterStatus.Active)
            .OrderBy(member => member.Name)
            .ToList();
        var incoming = roster.Where(
                member =>
                    (member.RosterStatus is RosterStatus.Camp or RosterStatus.Unrecruited) &&
                    member.RosterStatus.CanBeActive())
            .OrderBy(member => member.Name)
            .ToList();
        PartyScreen.Roster.PartySwapIncomingPicker.ItemsSource = incoming;
        PartyScreen.Roster.PartySwapOutgoingPicker.ItemsSource = active;
        PartyScreen.Roster.PartySwapPanel.Visibility =
            active.Count == 4 && incoming.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        if (selectedPartyMemberId is not null)
        {
            RenderPartyMemberDetail();
            if (PartyScreen.Abilities.PartyAbilityPanel.Visibility == Visibility.Visible)
            {
                RenderPartyAbilityPage();
            }

            if (PartyScreen.ManualBuild.ManualBuildPanel.Visibility == Visibility.Visible)
            {
                RenderManualBuildPage();
            }
        }

        PartyScreen.BuildImport.PartyImportBuildButton.IsEnabled =
            openRouterKeyConfigured;
    }

}
