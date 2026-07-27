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
    private DollCell? selectedLoadoutCell;

    private void RenderLoadout()
    {
        var member = controller.ActiveParty.FirstOrDefault(
                         candidate => candidate.Id == selectedLoadoutMemberId) ??
                     controller.ActiveParty.FirstOrDefault();
        selectedLoadoutMemberId = member?.Id;
        LoadoutScreen.LoadoutPartyStrip.ItemsSource = controller.ActiveParty
            .Select(
                candidate => new LoadoutMemberRow(
                    candidate,
                    candidate.Id == selectedLoadoutMemberId))
            .ToList();
        LoadoutScreen.LoadoutActText.Text =
            $"LOADOUT · ACT {controller.Run.SelectedAct ?? 1}";
        if (member is null)
        {
            ResetLoadoutDetail();
            LoadoutScreen.LoadoutMemberSummaryText.Text = "No active party members";
            LoadoutScreen.LoadoutGearGrid.ItemsSource = null;
            LoadoutScreen.LoadoutEmptyText.Text = "Add an active character in Party first.";
            LoadoutScreen.LoadoutEmptyPanel.Visibility = Visibility.Visible;
            return;
        }

        var build = controller.Builds.FirstOrDefault(
            candidate => candidate.Id == member.BuildId);
        LoadoutScreen.LoadoutMemberSummaryText.Text =
            build is null
                ? $"L{member.Level} · no build assigned"
                : $"L{member.Level} · {build.Name}";
        if (build is null)
        {
            ResetLoadoutDetail();
            LoadoutScreen.LoadoutGearGrid.ItemsSource = null;
            LoadoutScreen.LoadoutEmptyText.Text = $"{member.Name} has no build yet.";
            LoadoutScreen.LoadoutEmptyPanel.Visibility = Visibility.Visible;
            LoadoutScreen.LoadoutConfirmedText.Text = string.Empty;
            return;
        }

        LoadoutScreen.LoadoutEmptyPanel.Visibility = Visibility.Collapsed;
        var gear = PartyPlanningRules.WantedGear(
                controller.Run,
                member,
                controller.Run.SelectedAct ?? 1,
                controller.Builds,
                controller.Guide.Items)
            .Where(
                item =>
                    LoadoutSlotClassifier.Classify(item.Slot, item.Item) !=
                    LoadoutSlot.Extras)
            .ToList();
        var grouped = gear
            .GroupBy(
                item => LoadoutSlotClassifier.Classify(item.Slot, item.Item))
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<BuildGear>)group.ToList());
        var rows = DollCell.PaperDollRows
            .SelectMany(row => row)
            .Select(
                cell => LoadoutGearRow.For(
                    cell,
                    cell.Items(grouped),
                    member,
                    controller.Run,
                    controller.TargetContext))
            .ToList();
        LoadoutScreen.LoadoutGearGrid.ItemsSource = rows;
        var confirmable = gear.Where(item => item.IsMapObjective).ToList();
        var confirmed = confirmable.Count(
            item => controller.Run.EquipmentOwnerId(item.ItemKey) == member.Id);
        LoadoutScreen.LoadoutConfirmedText.Text = confirmable.Count == 0
            ? string.Empty
            : $"{confirmed}/{confirmable.Count} confirmed";

        if (selectedLoadoutGear is not null)
        {
            selectedLoadoutGear = gear.FirstOrDefault(
                item => item.Id == selectedLoadoutGear.Id);
            if (selectedLoadoutGear is not null)
            {
                RenderGearDetail();
            }
            else
            {
                ResetLoadoutDetail();
            }
        }
    }

    internal void OnLoadoutMemberClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button
            {
                DataContext: LoadoutMemberRow row,
            })
        {
            selectedLoadoutMemberId = row.Member.Id;
            selectedLoadoutGear = null;
            selectedLoadoutCell = null;
            RenderLoadout();
        }
    }

    internal void OnEditLoadoutMemberClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PlannerTabs.SelectedIndex = 2;
        if (selectedLoadoutMemberId is { } memberId)
        {
            PartyScreen.Landing.PartyGrid.SelectedItem = controller.ActiveParty.FirstOrDefault(
                member => member.Id == memberId);
        }
    }

    internal void OnLoadoutGearClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is not Button
            {
                DataContext: LoadoutGearRow { Gear: { } gear } row,
            })
        {
            return;
        }

        selectedLoadoutGear = gear;
        selectedLoadoutCell = row.Cell;
        LoadoutScreen.GearDetailPanel.Visibility = Visibility.Visible;
        RenderGearDetail();
        LoadoutScreen.LoadoutMainColumn.Width = new GridLength(0D);
        LoadoutScreen.LoadoutDetailColumn.Width = new GridLength(1D, GridUnitType.Star);
    }

    private void RenderGearDetail()
    {
        if (selectedLoadoutGear is not { } gear ||
            controller.ActiveParty.FirstOrDefault(
                member => member.Id == selectedLoadoutMemberId) is not { } member)
        {
            return;
        }

        var equipped =
            controller.Run.EquipmentOwnerId(gear.ItemKey) == member.Id;
        var targeted =
            controller.TargetContext?.Matches(gear.Id, member.Id) == true;
        LoadoutScreen.GearDetailIcon.Source = string.IsNullOrWhiteSpace(gear.Icon)
            ? null
            : AssetImage.Load(
                "ItemIcons",
                Path.ChangeExtension(Path.GetFileName(gear.Icon), ".png"));
        LoadoutScreen.GearDetailTitleText.Text = gear.Item;
        LoadoutScreen.GearDetailMetaText.Text =
            $"{member.Name} · {gear.Slot} · Act {gear.Act}";
        LoadoutScreen.GearDetailStatusText.Text =
            targeted ? "TARGET" : equipped ? "EQUIPPED" : gear.Priority.ToUpperInvariant();
        LoadoutScreen.GearDetailEffectText.Text = string.IsNullOrWhiteSpace(gear.Effect)
            ? string.Empty
            : $"★  {gear.Effect}";
        LoadoutScreen.GearDetailAcquisitionText.Text =
            $"→  {GearLogic.AcquireText(gear)}";
        LoadoutScreen.GearDetailWhyText.Text = $"◆  {gear.Why}";
        LoadoutScreen.GearDetailRequirementText.Text = gear.Requirement ?? string.Empty;
        LoadoutScreen.GearTargetButton.Content =
            targeted ? "Clear target" : "Set as target";
        LoadoutScreen.GearTargetButton.IsEnabled =
            targeted || !equipped &&
            gear.Act == (controller.Run.SelectedAct ?? 1) &&
            member.BuildId is not null;
        LoadoutScreen.GearEquippedButton.Content =
            equipped ? "✓  Equipped" : "○  Mark equipped";
        LoadoutScreen.GearEquippedButton.IsEnabled = gear.IsMapObjective;

        var cell = selectedLoadoutCell ??
                   new DollCell(
                       LoadoutSlotClassifier.Classify(gear.Slot, gear.Item));
        var overrideItem = PartyPlanningRules.SlotOverride(
            controller.Run,
            member,
            cell,
            controller.Guide.Items);
        LoadoutScreen.GearChangePicker.ItemsSource = controller.Guide.Items
            .Where(
                item =>
                    item.Act <= (controller.Run.SelectedAct ?? 1) &&
                    item.ItemKey != gear.ItemKey &&
                    LoadoutSlotClassifier.Classify(item.Slot, item.Name) == cell.Slot)
            .OrderBy(item => item.Name, StringComparer.Ordinal)
            .ToList();
        LoadoutScreen.GearChangePicker.SelectedItem = null;
        LoadoutScreen.GearRevertPickButton.Visibility =
            overrideItem is null ? Visibility.Collapsed : Visibility.Visible;

        var conflict = PartyPlanningRules.Conflict(
            controller.Run,
            gear,
            member,
            controller.Builds,
            controller.Guide.Items);
        LoadoutScreen.GearConflictPanel.Visibility =
            conflict is null ? Visibility.Collapsed : Visibility.Visible;
        LoadoutScreen.GearConflictText.Text = conflict?.Detail ?? string.Empty;
        var claimants = controller.ActiveParty
            .Where(
                candidate =>
                    PartyPlanningRules.WantedGear(
                            controller.Run,
                            candidate,
                            controller.Run.SelectedAct ?? 1,
                            controller.Builds,
                            controller.Guide.Items)
                        .Any(item => item.ItemKey == gear.ItemKey))
            .OrderBy(candidate => candidate.Name, StringComparer.Ordinal)
            .ToList();
        LoadoutScreen.GearGiveToPicker.ItemsSource = claimants;
        LoadoutScreen.GearGiveToPicker.SelectedItem = claimants.FirstOrDefault(
            candidate =>
                candidate.Id == PartyPlanningRules.PlannedOwnerId(
                    controller.Run,
                    gear.ItemKey,
                    controller.Builds,
                    controller.Guide.Items));
    }

    internal async void OnGearTargetClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedLoadoutGear is not { } gear ||
            controller.ActiveParty.FirstOrDefault(
                member => member.Id == selectedLoadoutMemberId) is not { } member)
        {
            return;
        }

        if (controller.TargetContext?.Matches(gear.Id, member.Id) == true)
        {
            await controller.ClearGearTargetAsync();
        }
        else
        {
            await controller.SetGearTargetAsync(member.Id, gear);
        }
    }

    internal async void OnGearEquippedClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedLoadoutGear is { } gear &&
            selectedLoadoutMemberId is { } memberId)
        {
            await controller.ToggleGearEquippedAsync(memberId, gear);
        }
    }

    internal async void OnUseLoadoutPickClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedLoadoutMemberId is not { } memberId ||
            selectedLoadoutCell is not { } cell ||
            LoadoutScreen.GearChangePicker.SelectedItem is not ItemSummary item ||
            !await controller.SetSlotOverrideAsync(memberId, cell, item.ItemKey))
        {
            return;
        }

        CloseLoadoutDetailAfterPlanChange();
    }

    internal async void OnRevertLoadoutPickClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedLoadoutMemberId is not { } memberId ||
            selectedLoadoutCell is not { } cell ||
            !await controller.SetSlotOverrideAsync(memberId, cell, itemKey: null))
        {
            return;
        }

        CloseLoadoutDetailAfterPlanChange();
    }

    internal async void OnGiveLoadoutGearClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedLoadoutGear is not { } gear ||
            LoadoutScreen.GearGiveToPicker.SelectedItem is not PartyMember member)
        {
            return;
        }

        await controller.SetGearAssignmentOverrideAsync(gear, member.Id);
    }

    internal void OnGearMapClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        OpenCurrentActMap();
    }

    internal void OnLoadoutBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        LoadoutScreen.LoadoutDetailColumn.Width = new GridLength(0D);
        LoadoutScreen.LoadoutMainColumn.Width = new GridLength(1D, GridUnitType.Star);
        LoadoutScreen.GearDetailPanel.Visibility = Visibility.Visible;
        buildImportAssignMemberId = null;
    }

    private void CloseLoadoutDetailAfterPlanChange()
    {
        ResetLoadoutDetail();
        RenderLoadout();
    }

    private void ResetLoadoutDetail()
    {
        selectedLoadoutGear = null;
        selectedLoadoutCell = null;
        LoadoutScreen.LoadoutDetailColumn.Width = new GridLength(0D);
        LoadoutScreen.LoadoutMainColumn.Width = new GridLength(1D, GridUnitType.Star);
    }
}
