using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class AbilitySourceRulesTests
{
    [Fact]
    public void UniquePermanentSourceMovesBetweenPartyMembers()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        SetLevel(run, "tav", 3);
        SetLevel(run, "companion-1", 3);
        var source = Source(
            "hags-hair",
            AbilityPlanSourceKind.Permanent,
            unique: true,
            minimumAct: 2,
            minimumLevel: 3);

        Assert.False(
            AbilitySourceRules.TrySet(
                run,
                source,
                true,
                "tav",
                selectedAct: 1,
                out var error));
        Assert.Contains("Act 2", error);

        Assert.True(
            AbilitySourceRules.TrySet(
                run,
                source,
                true,
                "tav",
                selectedAct: 2,
                out error));
        Assert.Null(error);
        Assert.Equal(
            "tav",
            AbilitySourceRules.Owner(
                source,
                run.Roster!,
                run.EquippedByMember! )?.Id);

        Assert.True(
            AbilitySourceRules.TrySet(
                run,
                source,
                true,
                "companion-1",
                selectedAct: 2,
                out error));
        Assert.Empty(
            run.Roster!.Single(member => member.Id == "tav")
                .AbilityModifiers!);
        Assert.Equal(
            "companion-1",
            AbilitySourceRules.Owner(
                source,
                run.Roster!,
                run.EquippedByMember!)?.Id);
    }

    [Fact]
    public void ConsumableReplacesExistingTemporaryModifier()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        var index = run.Roster!.FindIndex(member => member.Id == "tav");
        run.Roster[index] = run.Roster[index] with
        {
            AbilityModifiers =
            [
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Temporary,
                    AbilityModifierMode.Minimum,
                    21,
                    "Old elixir"),
            ],
        };
        var source = Source(
            "new-elixir",
            AbilityPlanSourceKind.Consumable,
            unique: false);

        Assert.True(
            AbilitySourceRules.TrySet(
                run,
                source,
                true,
                "tav",
                1,
                out _));

        var modifier = Assert.Single(
            run.Roster.Single(member => member.Id == "tav")
                .AbilityModifiers!);
        Assert.Equal("new-elixir", modifier.PlanSourceId);
        Assert.Equal(AbilityModifierKind.Temporary, modifier.Kind);
    }

    [Fact]
    public void EquipmentOwnerUsesPersistedLoadout()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        run.ToggleEquipment("gloves", "companion-2");
        var source = Source(
            "gloves-source",
            AbilityPlanSourceKind.Equipment,
            unique: true,
            itemKey: "gloves");

        Assert.Equal(
            "companion-2",
            AbilitySourceRules.Owner(
                source,
                run.Roster!,
                run.EquippedByMember!)?.Id);
    }

    private static void SetLevel(HonorRun run, string id, int level)
    {
        var index = run.Roster!.FindIndex(member => member.Id == id);
        run.Roster[index] = run.Roster[index] with { Level = level };
        run.SyncActivePartyProjection();
    }

    private static AbilityPlanSource Source(
        string id,
        AbilityPlanSourceKind kind,
        bool unique,
        int minimumAct = 1,
        int minimumLevel = 1,
        string? itemKey = null) =>
        new()
        {
            Id = id,
            Ability = Ability.Strength,
            Kind = kind,
            Mode = AbilityModifierMode.Add,
            Value = 1,
            Label = id,
            UniqueAcrossParty = unique,
            MinimumAct = minimumAct,
            MinimumLevel = minimumLevel,
            ItemKey = itemKey,
        };
}
