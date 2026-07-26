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
    private void RenderPartyAbilityPage()
    {
        if (SelectedPartyMember() is not { } member)
        {
            return;
        }

        var build = controller.Builds.FirstOrDefault(
            candidate => candidate.Id == member.BuildId);
        var setups = build?.AbilitySetups ?? [];
        var active = AbilityProgression.ActiveSetup(build, member.Level);
        var selected = setups.FirstOrDefault(
                           setup => setup.Id == selectedAbilitySetupId) ??
                       active ??
                       setups.FirstOrDefault();
        selectedAbilitySetupId = selected?.Id;
        PartyScreen.Abilities.AbilityMemberNameText.Text = member.Name;
        PartyScreen.Abilities.AbilitySetupPicker.ItemsSource = setups;
        PartyScreen.Abilities.AbilitySetupPicker.SelectedItem = selected;

        if (selected is null)
        {
            PartyScreen.Abilities.AbilityRecipeLabelText.Text = "NO VALIDATED ABILITY POINTS RECIPE";
            PartyScreen.Abilities.AbilityRecipeInstructionText.Text =
                "The selected build does not specify point buy and +2/+1 bonuses.";
            PartyScreen.Abilities.AbilityRecipeValidityText.Text = "UNAVAILABLE";
            PartyScreen.Abilities.AbilityPointBuyText.Text = string.Empty;
            PartyScreen.Abilities.AbilityBonusText.Text = string.Empty;
            PartyScreen.Abilities.AbilityFinalText.Text = string.Empty;
            PartyScreen.Abilities.AbilityClassOrderText.Text = string.Empty;
            PartyScreen.Abilities.AbilityReasonText.Text = string.Empty;
            PartyScreen.Abilities.ApplyAbilitySetupButton.IsEnabled = false;
        }
        else
        {
            var valid = AbilityProgression.IsValidBg3Setup(selected);
            var cost = AbilityProgression.PointBuyCost(selected.PointBuyScores);
            var isCurrent = selected.Id == active?.Id;
            var applied = member.AppliedAbilitySetupId == selected.Id;
            PartyScreen.Abilities.AbilityRecipeLabelText.Text = selected.Label.ToUpperInvariant();
            PartyScreen.Abilities.AbilityRecipeInstructionText.Text =
                isCurrent ? "Enter these values in BG3 now" : "Reference setup";
            PartyScreen.Abilities.AbilityRecipeValidityText.Text =
                valid ? $"{cost}/27 VALID" : "INVALID";
            PartyScreen.Abilities.AbilityPointBuyText.Text =
                $"1  Point buy   {selected.PointBuyScores.Summary}";
            PartyScreen.Abilities.AbilityBonusText.Text =
                $"2  Bonus       +2 {selected.BonusTwo} · +1 {selected.BonusOne}";
            PartyScreen.Abilities.AbilityFinalText.Text =
                $"3  Enter       {selected.FinalScores.Summary}";
            PartyScreen.Abilities.AbilityClassOrderText.Text =
                $"1  First class: {selected.FirstClass}\n2  {selected.ClassOrder}";
            PartyScreen.Abilities.AbilityReasonText.Text = $"◆ {selected.Reason}";
            PartyScreen.Abilities.ApplyAbilitySetupButton.Content = applied
                ? "✓  Recorded in BG3"
                : "Mark these values applied in BG3";
            PartyScreen.Abilities.ApplyAbilitySetupButton.IsEnabled =
                isCurrent && valid && !applied;
        }

        var target = build?.TargetAbilityScores;
        PartyScreen.Abilities.AbilityRecordedScoresText.Text =
            target is null
                ? member.EffectiveAbilityScores.Summary
                : $"{member.EffectiveAbilityScores.Summary}\nGoal: {target.Summary}";
        var rows = (build?.AbilitySources ?? [])
            .Select(source => AbilitySourceRow.For(
                source,
                member,
                controller.Run,
                controller.Run.SelectedAct ?? 1))
            .ToList();
        PartyScreen.Abilities.AbilitySourceList.ItemsSource = rows;
        PartyScreen.Abilities.AbilitySourcesEmptyText.Visibility =
            rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    internal void OnAbilitySetupChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            PartyScreen.Abilities.AbilitySetupPicker.SelectedItem is not AbilitySetupPlan setup)
        {
            return;
        }

        selectedAbilitySetupId = setup.Id;
        RenderPartyAbilityPage();
    }

    internal async void OnApplyAbilitySetupClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedPartyMemberId is not null &&
            PartyScreen.Abilities.AbilitySetupPicker.SelectedItem is AbilitySetupPlan setup)
        {
            await controller.ApplyAbilitySetupAsync(
                selectedPartyMemberId,
                setup);
        }
    }

    internal async void OnAbilitySourceActionClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (selectedPartyMemberId is null ||
            sender is not Button { DataContext: AbilitySourceRow row })
        {
            return;
        }

        if (row.Source.Kind == AbilityPlanSourceKind.Equipment)
        {
            PlannerTabs.SelectedIndex = 3;
            return;
        }

        var error = await controller.SetAbilitySourceAsync(
            selectedPartyMemberId,
            row.Source,
            !row.Applied);
        if (error is not null)
        {
            ShowError(error);
        }
    }
}
