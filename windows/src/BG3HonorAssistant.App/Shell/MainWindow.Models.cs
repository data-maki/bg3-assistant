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
    private sealed record ChatLineRow(
        string Role,
        string Text,
        IReadOnlyList<ChatSource> Sources,
        bool IsError);

    private sealed record ActGearRow(BuildGear Gear, bool CanEdit)
    {
        public string Detail => $"{Gear.Region} · {Gear.Acquisition}";

        public Visibility ActionVisibility =>
            CanEdit ? Visibility.Visible : Visibility.Collapsed;
    }

    private sealed record AbilitySourceRow(
        AbilityPlanSource Source,
        string Ability,
        string Label,
        string Detail,
        string Action,
        bool CanAct,
        bool Applied)
    {
        public static AbilitySourceRow For(
            AbilityPlanSource source,
            PartyMember member,
            HonorRun run,
            int selectedAct)
        {
            var equipped = run.EquippedByMember?.GetValueOrDefault(member.Id) ??
                           [];
            var applied = AbilitySourceRules.IsApplied(
                source,
                member,
                equipped);
            var future =
                member.Level < source.MinimumLevel ||
                selectedAct < source.MinimumAct;
            var action = source.Kind switch
            {
                AbilityPlanSourceKind.Asi or AbilityPlanSourceKind.Feat =>
                    future ? $"L{source.MinimumLevel}" : "Planned",
                AbilityPlanSourceKind.Equipment =>
                    applied ? "Equipped" : "Loadout",
                _ => applied ? "Recorded" : future ? $"L{source.MinimumLevel}" : "Record",
            };
            var canAct = source.Kind switch
            {
                AbilityPlanSourceKind.Equipment => !applied,
                AbilityPlanSourceKind.Permanent or
                    AbilityPlanSourceKind.Consumable => !future,
                _ => false,
            };
            var effect = source.Mode == AbilityModifierMode.Add
                ? $"+{source.Value}"
                : $"→ {source.Value}";
            return new AbilitySourceRow(
                source,
                AbilityLabel(source.Ability),
                $"{source.Label}  {effect}",
                $"{source.Kind} · Act {source.MinimumAct}, L{source.MinimumLevel}. " +
                source.Note,
                action,
                canAct,
                applied);
        }
    }

    private sealed record ManualAbilityRow(
        Ability Ability,
        string Label,
        int Value);

    private sealed record ManualLevelRow(
        int Level,
        string Heading,
        string Summary,
        string SelectedClass,
        IReadOnlyList<string> Classes)
    {
        public static ManualLevelRow For(
            ManualBuildLevel level,
            ManualBuildPlan plan,
            IReadOnlyList<string> classes)
        {
            var classLevel = plan.ClassLevel(level.CharacterLevel);
            var definition = ClassCatalog.Definitions.FirstOrDefault(
                item => item.Name == level.ClassName);
            var summary = definition is not null &&
                          definition.Levels.TryGetValue(
                              classLevel,
                              out var levelDefinition)
                ? string.Join(
                    " · ",
                    levelDefinition.Features.Select(feature => feature.Name)
                        .Concat(level.Selections.Values.SelectMany(value => value)))
                : "No choices recorded";
            return new ManualLevelRow(
                level.CharacterLevel,
                string.IsNullOrWhiteSpace(level.ClassName)
                    ? "Choose class"
                    : $"{level.ClassName} {classLevel}",
                string.IsNullOrWhiteSpace(summary)
                    ? "No new selection at this class level"
                    : summary,
                level.ClassName,
                classes);
        }
    }

    private sealed record ManualChoiceRow(
        BuildChoiceGroup Group,
        string Label,
        string Detail,
        bool Selected);

    private sealed record BuildPickerRow(
        string? BuildId,
        string Label);

    private sealed record DifficultyPickerRow(
        RunDifficulty Value,
        string Label);

    private sealed record RevealPickerRow(
        RouteRevealPolicy Value,
        string Label);

    private sealed record SavedRunPickerRow(
        SavedRun Run,
        string Label);

    private sealed record OnboardingLandmarkRow(
        string? CheckpointId,
        string Name,
        string Note)
    {
        public string Glyph => CheckpointId is null ? "◉" : "○";
    }

    private sealed record LoadoutMemberRow(
        PartyMember Member,
        bool IsSelected)
    {
        public string Name => Member.Name;

        public string? BuildId => Member.BuildId;
    }

    private sealed record LoadoutGearRow(
        DollCell Cell,
        BuildGear? Gear,
        string ItemName,
        string Region,
        string? Icon,
        string SlotGlyph,
        string StatusGlyph,
        bool HasItem)
    {
        public static LoadoutGearRow For(
            DollCell cell,
            IReadOnlyList<BuildGear> items,
            PartyMember member,
            HonorRun run,
            GearTargetContext? target)
        {
            var gear = items.FirstOrDefault();
            var owner = gear is null
                ? null
                : run.EquipmentOwnerId(gear.ItemKey);
            var status = gear is null
                ? string.Empty
                : target?.Matches(gear.Id, member.Id) == true
                    ? "◎"
                    : owner == member.Id
                        ? "✓"
                        : owner is not null
                            ? "↔"
                            : "○";
            var name = gear is null
                ? cell.EmptyLabel
                : items.Count > 1
                    ? $"{gear.Item} +{items.Count - 1}"
                    : gear.Item;
            return new LoadoutGearRow(
                cell,
                gear,
                name,
                gear?.Region ?? string.Empty,
                gear?.Icon,
                GlyphForSlot(cell.Slot),
                status,
                gear is not null);
        }

        private static string GlyphForSlot(LoadoutSlot slot) =>
            slot switch
            {
                LoadoutSlot.Helmet => "♜",
                LoadoutSlot.Cloak => "◢",
                LoadoutSlot.Armour => "♟",
                LoadoutSlot.Gloves => "✥",
                LoadoutSlot.Boots => "⌁",
                LoadoutSlot.Instrument => "♫",
                LoadoutSlot.Amulet => "◇",
                LoadoutSlot.Rings => "○",
                LoadoutSlot.MainHand => "†",
                LoadoutSlot.OffHand => "◈",
                LoadoutSlot.Ranged => "⌁",
                _ => "·",
            };
    }
}
