using System.ComponentModel;
using System.IO;
using System.Text.Json;
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
using BG3HonorAssistant.Core.Serialization;
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
using ComboBox = System.Windows.Controls.ComboBox;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    internal async void OnRosterStatusChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (refreshing ||
            sender is not ComboBox
            {
                DataContext: PartyMember member,
                SelectedItem: ComboBoxItem selected,
            } ||
            selected.Tag is not string raw ||
            !Enum.TryParse<RosterStatus>(raw, out var status) ||
            status == member.RosterStatus)
        {
            return;
        }

        var previousPlan = controller.Run.GetPartyPlan();
        if (!await controller.SetRosterStatusAsync(member.Id, status))
        {
            ShowError(status == RosterStatus.Active
                ? "The active party already has four members."
                : $"Could not change {member.Name}'s roster status.");
            RefreshView();
        }
        else
        {
            RecordPartyUndo(
                $"Moved {member.Name} to " +
                (status == RosterStatus.Unrecruited ? "Not recruited" : status),
                previousPlan);
        }
    }

    internal async void OnSwapActivePartyClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyScreen.Roster.PartySwapIncomingPicker.SelectedItem is not PartyMember incoming ||
            PartyScreen.Roster.PartySwapOutgoingPicker.SelectedItem is not PartyMember outgoing)
        {
            ShowError("Choose who joins and who returns to camp.");
            return;
        }

        var previousPlan = controller.Run.GetPartyPlan();
        if (await controller.SwapActivePartyAsync(incoming.Id, outgoing.Id))
        {
            RecordPartyUndo(
                $"Swapped {incoming.Name} for {outgoing.Name}",
                previousPlan);
        }
        else
        {
            ShowError("That active-party swap could not be applied.");
        }
    }

    internal async void OnUndoPartyChangeClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (partyUndoPlan is null || partyUndoRunId != controller.Run.Id)
        {
            ClearPartyUndo();
            return;
        }

        var plan = partyUndoPlan;
        ClearPartyUndo();
        await controller.RestorePartyPlanAsync(plan);
    }

    internal void OnDismissPartyUndoClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        ClearPartyUndo();
    }

    private void RecordPartyUndo(string message, PartyPlan previousPlan)
    {
        partyUndoPlan = previousPlan;
        partyUndoExpectedSignature = PartyPlanSignature(
            controller.Run.GetPartyPlan());
        partyUndoRunId = controller.Run.Id;
        PartyScreen.PartyUndoText.Text = message;
        PartyScreen.PartyUndoBanner.Visibility = Visibility.Visible;
    }

    private void ClearPartyUndo()
    {
        partyUndoPlan = null;
        partyUndoExpectedSignature = null;
        partyUndoRunId = null;
        PartyScreen.PartyUndoBanner.Visibility = Visibility.Collapsed;
    }

    private void InvalidatePartyUndoIfStateChanged()
    {
        if (partyUndoPlan is not null &&
            partyUndoExpectedSignature != PartyPlanSignature(
                controller.Run.GetPartyPlan()))
        {
            ClearPartyUndo();
        }
    }

    private static string PartyPlanSignature(PartyPlan plan) =>
        JsonSerializer.Serialize(plan, JsonDefaults.Create());

    private async void OnLevelDownClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyScreen.Landing.PartyGrid.SelectedItem is PartyMember member)
        {
            await controller.SetPartyLevelAsync(member.Id, member.Level - 1);
        }
    }

    private async void OnLevelUpClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyScreen.Landing.PartyGrid.SelectedItem is PartyMember member)
        {
            await controller.SetPartyLevelAsync(member.Id, member.Level + 1);
        }
    }

    private async void OnSendToCampClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyScreen.Landing.PartyGrid.SelectedItem is PartyMember member &&
            !await controller.SetRosterStatusAsync(member.Id, RosterStatus.Camp))
        {
            ShowError("That roster status could not be applied.");
        }
    }

    private async void OnMakeActiveClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyScreen.Landing.PartyGrid.SelectedItem is PartyMember member &&
            !await controller.SetRosterStatusAsync(member.Id, RosterStatus.Active))
        {
            ShowError(
                "The active party is full or this member is unavailable. " +
                "Send someone to camp or confirm the member's story status first.");
        }
    }
}
