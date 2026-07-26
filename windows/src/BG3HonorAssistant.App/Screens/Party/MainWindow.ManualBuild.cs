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
    private void RenderManualBuildPage()
    {
        if (SelectedPartyMember() is not
            {
                ManualBuild: { } plan,
            } member)
        {
            return;
        }

        PartyScreen.ManualBuild.ManualDifficultyText.Text =
            (controller.Run.Difficulty ?? RunDifficulty.Honour)
            .ToString()
            .ToUpperInvariant();
        if (!PartyScreen.ManualBuild.ManualBuildNameTextBox.IsKeyboardFocusWithin)
        {
            PartyScreen.ManualBuild.ManualBuildNameTextBox.Text = plan.Name;
        }

        PartyScreen.ManualBuild.ManualBuildClassSummaryText.Text =
            string.IsNullOrWhiteSpace(plan.ClassSummary)
                ? "Choose a class at Level 1 to begin."
                : plan.ClassSummary;
        var spent = AbilityProgression.PointBuyCost(plan.AbilityScores);
        PartyScreen.ManualBuild.ManualPointBuyStatusText.Text =
            spent < 0 ? "8–15 EACH" : $"{spent}/27 SPENT";
        PartyScreen.ManualBuild.ManualPointBuyStatusText.Foreground =
            spent == 27
                ? FindResource("BG3SuccessBrush") as Brush
                : FindResource("BG3WarningBrush") as Brush;
        PartyScreen.ManualBuild.ManualAbilityList.ItemsSource = Enum.GetValues<Ability>()
            .Select(
                ability => new ManualAbilityRow(
                    ability,
                    AbilityLabel(ability),
                    plan.AbilityScores.Get(ability)))
            .ToList();
        PartyScreen.ManualBuild.ManualCurrentLevelText.Text = $"Current L{member.Level}";
        var classes = ClassCatalog.Definitions.Select(item => item.Name).ToList();
        var firstClass = plan.Levels.FirstOrDefault()?.ClassName;
        if (controller.Run.Difficulty == RunDifficulty.Explorer &&
            !string.IsNullOrWhiteSpace(firstClass))
        {
            classes = [firstClass];
        }

        var rows = plan.Levels.Select(
                level => ManualLevelRow.For(level, plan, classes))
            .ToList();
        PartyScreen.ManualBuild.ManualLevelList.ItemsSource = rows;
        PartyScreen.ManualBuild.ManualLevelList.SelectedItem = rows.FirstOrDefault(
            row => row.Level == selectedManualLevel);
        RenderManualChoices();
    }

    internal async void OnManualBuildNameLostFocus(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (selectedPartyMemberId is not null)
        {
            await controller.RenameManualBuildAsync(
                selectedPartyMemberId,
                PartyScreen.ManualBuild.ManualBuildNameTextBox.Text);
        }
    }

    internal async void OnManualAbilityAdjustClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (selectedPartyMemberId is null ||
            sender is not Button
            {
                DataContext: ManualAbilityRow row,
                Tag: string rawDelta,
            } ||
            !int.TryParse(rawDelta, out var delta))
        {
            return;
        }

        await controller.SetManualAbilityAsync(
            selectedPartyMemberId,
            row.Ability,
            row.Value + delta);
    }

    internal void OnManualLevelSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            PartyScreen.ManualBuild.ManualLevelList.SelectedItem is not ManualLevelRow row)
        {
            return;
        }

        selectedManualLevel = row.Level;
        RenderManualChoices();
    }

    internal async void OnManualClassChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (refreshing ||
            selectedPartyMemberId is null ||
            sender is not ComboBox
            {
                DataContext: ManualLevelRow row,
                SelectedItem: string className,
            } ||
            string.IsNullOrWhiteSpace(className) ||
            className == row.SelectedClass)
        {
            return;
        }

        if (!await controller.SetManualClassAsync(
                selectedPartyMemberId,
                row.Level,
                className))
        {
            ShowError("Explorer difficulty does not allow multiclassing.");
            RefreshView();
        }
    }

    private void RenderManualChoices()
    {
        if (SelectedPartyMember() is not { ManualBuild: { } plan } ||
            plan.Levels.FirstOrDefault(
                level => level.CharacterLevel == selectedManualLevel) is
                not { } saved ||
            ClassCatalog.Definitions.FirstOrDefault(
                definition => definition.Name == saved.ClassName) is
                not { } definition)
        {
            PartyScreen.ManualBuild.ManualChoicesPanel.Visibility = Visibility.Collapsed;
            PartyScreen.ManualBuild.ManualChoiceList.ItemsSource = null;
            return;
        }

        var classLevel = plan.ClassLevel(selectedManualLevel);
        if (!definition.Levels.TryGetValue(classLevel, out var levelDefinition))
        {
            PartyScreen.ManualBuild.ManualChoicesPanel.Visibility = Visibility.Collapsed;
            PartyScreen.ManualBuild.ManualChoiceList.ItemsSource = null;
            return;
        }

        var rows = levelDefinition.Choices
            .SelectMany(
                group => group.Options.Select(
                    option => new ManualChoiceRow(
                        group,
                        option.Name,
                        $"{group.Title} · choose {group.MaximumSelections}. " +
                        option.Detail,
                        saved.Selections.GetValueOrDefault(group.Id)?
                            .Contains(option.Name) == true)))
            .ToList();
        PartyScreen.ManualBuild.ManualChoicesTitleText.Text =
            $"LEVEL {selectedManualLevel} · {saved.ClassName} {classLevel}";
        PartyScreen.ManualBuild.ManualChoiceList.ItemsSource = rows;
        PartyScreen.ManualBuild.ManualChoicesPanel.Visibility =
            rows.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    internal async void OnManualChoiceClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (selectedPartyMemberId is null ||
            sender is not CheckBox { DataContext: ManualChoiceRow row })
        {
            return;
        }

        await controller.ToggleManualChoiceAsync(
            selectedPartyMemberId,
            selectedManualLevel,
            row.Group,
            row.Label);
    }

    private static string AbilityLabel(Ability ability) =>
        ability switch
        {
            Ability.Strength => "STR",
            Ability.Dexterity => "DEX",
            Ability.Constitution => "CON",
            Ability.Intelligence => "INT",
            Ability.Wisdom => "WIS",
            Ability.Charisma => "CHA",
            _ => ability.ToString().ToUpperInvariant(),
        };
}
