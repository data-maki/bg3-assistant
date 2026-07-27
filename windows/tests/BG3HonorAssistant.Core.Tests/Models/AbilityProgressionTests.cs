using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class AbilityProgressionTests
{
    [Fact]
    public void RecordFormattingDoesNotRecurseThroughComputedAbilityScores()
    {
        var scores = new AbilityScores(17, 13, 15, 10, 12, 8);
        var member = Member(1) with { AbilityScores = scores };

        Assert.Equal(
            "STR 17 / DEX 13 / CON 15 / INT 10 / WIS 12 / CHA 8",
            scores.ToString());
        Assert.Contains("STR 17", member.ToString(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(7, -2)]
    [InlineData(8, -1)]
    [InlineData(9, -1)]
    [InlineData(10, 0)]
    [InlineData(19, 4)]
    [InlineData(20, 5)]
    public void ModifierUsesFloorForOddScores(int score, int expected)
    {
        Assert.Equal(expected, AbilityProgression.ModifierFor(score));
    }

    [Fact]
    public void LegacyChoiceTextContributesAfterLatestReset()
    {
        var build = Build(
            levels:
            [
                new BuildLevel(
                    1,
                    "Fighter",
                    string.Empty,
                    string.Empty,
                    string.Empty,
                    string.Empty,
                    new AbilityScores(17, 13, 15, 10, 12, 8)),
                new BuildLevel(
                    4,
                    "Fighter",
                    string.Empty,
                    "ASI +2 STR",
                    string.Empty,
                    string.Empty),
            ]);
        var member = Member(4) with
        {
            AbilityScores = new AbilityScores(17, 13, 15, 10, 12, 8),
        };

        var result = AbilityProgression.Breakdown(
            member,
            build,
            Ability.Strength);

        Assert.Equal(17, result.Starting);
        Assert.Equal(2, result.LevelGain);
        Assert.Equal(19, result.Current);
        Assert.Equal(19, result.Target);
    }

    [Fact]
    public void StructuredSourcesRespectAppliedSetupEquipmentAndModifierOrder()
    {
        var setup = Setup();
        var build = Build(
            levels:
            [
                new BuildLevel(
                    1,
                    "Fighter",
                    string.Empty,
                    string.Empty,
                    string.Empty,
                    string.Empty),
            ],
            setup,
            [
                Source(
                    "asi",
                    AbilityPlanSourceKind.Asi,
                    AbilityModifierMode.Add,
                    2,
                    minimumLevel: 4),
                Source(
                    "gloves",
                    AbilityPlanSourceKind.Equipment,
                    AbilityModifierMode.Minimum,
                    23,
                    itemKey: "gauntlets"),
            ]) with
        {
            TargetAbilityScores = new AbilityScores(24, 13, 15, 10, 12, 8),
        };
        var member = Member(5) with
        {
            AbilityScores = setup.FinalScores,
            AppliedAbilitySetupId = setup.Id,
            AbilityModifiers =
            [
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Permanent,
                    AbilityModifierMode.Add,
                    1,
                    "Reward"),
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Temporary,
                    AbilityModifierMode.Add,
                    2,
                    "Elixir"),
            ],
        };

        var result = AbilityProgression.Breakdown(
            member,
            build,
            Ability.Strength,
            new HashSet<string> { "gauntlets" });

        Assert.Equal(2, result.LevelGain);
        Assert.Equal(1, result.Permanent);
        Assert.Equal(3, result.Equipment);
        Assert.Equal(2, result.Temporary);
        Assert.Equal(25, result.Current);
        Assert.Equal(24, result.Target);
        Assert.Contains("1 above", result.Tooltip);
    }

    [Fact]
    public void StructuredLevelGainWaitsUntilSetupIsRecordedApplied()
    {
        var setup = Setup();
        var build = Build(
            [new BuildLevel(1, "Fighter", "", "", "", "")],
            setup,
            [
                Source(
                    "asi",
                    AbilityPlanSourceKind.Asi,
                    AbilityModifierMode.Add,
                    2,
                    minimumLevel: 4),
            ]);
        var member = Member(5) with { AbilityScores = setup.FinalScores };

        Assert.Equal(
            0,
            AbilityProgression
                .Breakdown(member, build, Ability.Strength)
                .LevelGain);
    }

    [Fact]
    public void NextFeatFindsTheFirstRecognizedFutureChoice()
    {
        var build = Build(
            [
                new BuildLevel(1, "Fighter", "", "", "", ""),
                new BuildLevel(4, "Fighter", "", "Sharpshooter", "", ""),
                new BuildLevel(6, "Fighter", "", "ASI +2 DEX", "", ""),
            ]);

        Assert.Equal(4, AbilityProgression.NextFeat(build, 1)?.Level);
        Assert.Equal(6, AbilityProgression.NextFeat(build, 4)?.Level);
        Assert.Null(AbilityProgression.NextFeat(build, 6));
    }

    private static PartyMember Member(int level) =>
        new()
        {
            Id = "tav",
            Name = "Tav",
            Level = level,
            ClassName = "Fighter",
        };

    private static AbilitySetupPlan Setup() =>
        new()
        {
            Id = "fighter-start",
            Level = 1,
            Label = "Start",
            Reason = "Oracle",
            PointBuyScores = new AbilityScores(15, 13, 15, 10, 12, 8),
            BonusTwo = Ability.Strength,
            BonusOne = Ability.Constitution,
            FinalScores = new AbilityScores(17, 13, 16, 10, 12, 8),
            FirstClass = "Fighter",
            ClassOrder = "Fighter",
        };

    private static AbilityPlanSource Source(
        string id,
        AbilityPlanSourceKind kind,
        AbilityModifierMode mode,
        int value,
        int minimumLevel = 1,
        string? itemKey = null) =>
        new()
        {
            Id = id,
            Ability = Ability.Strength,
            Kind = kind,
            Mode = mode,
            Value = value,
            Label = id,
            MinimumLevel = minimumLevel,
            ItemKey = itemKey,
        };

    private static BuildSummary Build(
        IReadOnlyList<BuildLevel> levels,
        AbilitySetupPlan? setup = null,
        IReadOnlyList<AbilityPlanSource>? sources = null) =>
        new()
        {
            Id = "build",
            Name = "Build",
            Levels = levels,
            StartingAbilityScores =
                new AbilityScores(17, 13, 15, 10, 12, 8),
            AbilitySetups = setup is null ? null : [setup],
            AbilitySources = sources,
        };
}
