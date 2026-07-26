using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class BuildImportTests
{
    [Fact]
    public void DraftProducesExplicitLegalStartingSetup()
    {
        var imported = MakeDraft("Monk 6 / Rogue 4 / Fighter 1 / Cleric 1")
            .Import(new Uri("https://example.com/build"));
        var setup = Assert.Single(imported.Build.AbilitySetups!);

        Assert.True(AbilityProgression.IsValidBg3Setup(setup));
        Assert.Equal(16, imported.Build.StartingAbilityScores?.Dexterity);
        Assert.Equal(16, imported.Build.StartingAbilityScores?.Wisdom);
        Assert.Equal(
            "STR 10 / DEX 16 / CON 15 / INT 8 / WIS 16 / CHA 8",
            imported.Build.StartingAbilities);
    }

    [Fact]
    public void DraftRejectsLevelTwelveClassSplitThatDoesNotTotalTwelve()
    {
        var exception = Assert.Throws<BuildImportException>(
            () => MakeDraft("Monk 8 / Rogue 4 / Fighter 1 / Cleric 1")
                .Import(new Uri("https://example.com/build")));

        Assert.Contains("totals 14, not 12", exception.Message);
    }

    [Fact]
    public void DraftRepairsInvalidSplitFromCumulativeClassLevels()
    {
        var source = MakeDraft("Monk 8 / Cleric 1 / Rogue 4");
        var takes = new[]
        {
            "Monk 1",
            "Monk 2",
            "Monk 3",
            "Monk 4",
            "Monk 5",
            "Cleric 1",
            "Monk 6",
            "Fighter 1",
            "Rogue 1",
            "Rogue 3",
            "Rogue 3",
            "Rogue 4",
        };
        var draft = source with
        {
            Levels = takes
                .Select(
                    (take, index) => new BuildImportLevel(
                        index + 1,
                        take,
                        string.Empty,
                        string.Empty,
                        string.Empty,
                        "Explicit"))
                .ToArray(),
        };

        var imported = draft.Import(new Uri("https://example.com/build"));

        Assert.Equal(
            "Monk 6 / Cleric 1 / Fighter 1 / Rogue 4",
            imported.Build.FinalSplit);
    }

    private static BuildImportDraft MakeDraft(string finalSplit) =>
        new()
        {
            Name = "Open Hand Monk",
            Role = "Mobile striker",
            FinalSplit = finalSplit,
            ClassProgression = "Monk, Rogue, Fighter, Cleric",
            PointBuyScores = new AbilityScores(10, 14, 15, 8, 15, 8),
            BonusTwo = Ability.Dexterity,
            BonusOne = Ability.Wisdom,
            PlayPattern = "Use unarmed attacks and control.",
            Caveat = "Requires a respec.",
            Levels =
            [
                new BuildImportLevel(
                    12,
                    "Cleric 1",
                    "War Domain",
                    string.Empty,
                    string.Empty,
                    "Explicit"),
            ],
            Gear = [],
        };
}
