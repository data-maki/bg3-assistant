using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class RunCreationTests
{
    private static readonly AbilityScores LatestScores =
        new(8, 16, 14, 10, 10, 17);

    [Fact]
    public void FreshRunKeepsCharacterAndLatestBuildPresetsOnly()
    {
        var source = new HonorRun();
        source.NormalizeRoster();
        source.SelectedAct = 3;
        source.StoryOutcomes = ["saved-grove"];
        source.WalkthroughProgress = new Dictionary<string, CheckpointDisposition>
        {
            ["step"] = CheckpointDisposition.Completed,
        };
        source.EquippedByMember = new Dictionary<string, HashSet<string>>
        {
            ["tav"] = ["old-item"],
        };
        source.GearTarget = new GearTarget("tav", "latest-build", "old-item");

        var tavIndex = source.Roster!.FindIndex(member => member.Id == "tav");
        source.Roster[tavIndex] = source.Roster[tavIndex] with
        {
            Name = "Ariadne",
            Level = 12,
            BuildId = "latest-build",
            ClassName = "Old class",
            AbilityScores = AbilityScores.CustomDefault,
            AbilityModifiers =
            [
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Permanent,
                    AbilityModifierMode.Add,
                    1,
                    "Old reward"),
            ],
            AppliedAbilitySetupId = "old-setup",
        };

        var shadowheartIndex = source.Roster.FindIndex(member => member.Name == "Shadowheart");
        source.Roster[shadowheartIndex] = source.Roster[shadowheartIndex] with
        {
            BuildId = "removed-build",
            Status = RosterStatus.Dead,
        };
        source.SyncActivePartyProjection();

        var createdAt = DateTimeOffset.FromUnixTimeSeconds(1234);
        var fresh = source.FreshRun(
            "New Run",
            "latest-guide",
            [LatestBuild()],
            createdAt);

        Assert.Empty(fresh.Progress);
        Assert.True(fresh.WalkthroughProgress is null or { Count: 0 });
        Assert.True(fresh.StoryOutcomes is null or { Count: 0 });
        Assert.True(fresh.EquippedByMember is null or { Count: 0 });
        Assert.Null(fresh.GearTarget);

        var tav = Assert.Single(fresh.Roster!, member => member.Id == "tav");
        Assert.Equal("Ariadne", tav.Name);
        Assert.Equal(1, tav.Level);
        Assert.Equal("latest-build", tav.BuildId);
        Assert.Equal("Bard 1", tav.ClassName);
        Assert.Equal(LatestScores, tav.AbilityScores);
        Assert.Empty(tav.AbilityModifiers!);
        Assert.Null(tav.AppliedAbilitySetupId);
        Assert.Equal(createdAt, fresh.BuildAssignedAt![tav.Id]);

        var shadowheart = Assert.Single(
            fresh.Roster!,
            member => member.Name == "Shadowheart");
        Assert.Null(shadowheart.BuildId);
        Assert.Equal(RosterStatus.Active, shadowheart.RosterStatus);
    }

    private static BuildSummary LatestBuild() =>
        new()
        {
            Id = "latest-build",
            Name = "Latest Swords Bard",
            HonorStatus = "Reviewed",
            Role = "Control",
            FinalSplit = "Bard 12",
            ClassProgression = "Bard 1-12",
            StartingAbilityScores = LatestScores,
            Levels =
            [
                new BuildLevel(1, "Bard 1", "-", string.Empty, string.Empty, "Reviewed"),
            ],
        };
}
