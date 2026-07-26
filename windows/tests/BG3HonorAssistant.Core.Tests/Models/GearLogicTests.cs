using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class GearLogicTests
{
    [Fact]
    public void LoadoutClassifiesCapeInstrumentAndTorchOutsideEquipmentGrid()
    {
        Assert.Equal(
            LoadoutSlot.Cloak,
            LoadoutSlotClassifier.Classify("Cloak", "Thunderskin Cloak"));
        Assert.Equal(
            LoadoutSlot.Instrument,
            LoadoutSlotClassifier.Classify("Instrument", "Spider's Lyre"));
        Assert.Equal(
            LoadoutSlot.Extras,
            LoadoutSlotClassifier.Classify("Melee", "Torch x2"));
    }

    [Fact]
    public void AssignmentPrefersEarliestBuildAssignment()
    {
        var result = GearLogic.Assignments(
            [
                Claim("karlach", "Zerker", 200, "caustic-band"),
                Claim("astarion", "Assassin", 100, "caustic-band"),
            ],
            new Dictionary<string, string>());

        Assert.Equal("astarion", result["caustic-band"]);
    }

    [Fact]
    public void OverrideBeatsRecency()
    {
        var result = GearLogic.Assignments(
            [
                Claim("karlach", "Zerker", 200, "caustic-band"),
                Claim("astarion", "Assassin", 100, "caustic-band"),
            ],
            new Dictionary<string, string>
            {
                ["caustic-band"] = "karlach",
            });

        Assert.Equal("karlach", result["caustic-band"]);
    }

    [Fact]
    public void RouteAndEquipmentTargetsReplaceEachOther()
    {
        var run = new HonorRun();
        run.FocusRoute("grove", "grove-fight");

        run.FocusGear(new GearTarget("tav", "cleric", "luminous-armour"));

        Assert.Null(run.FocusedWalkthroughStepId);
        Assert.Null(run.SelectedCheckpointId);
        Assert.Equal("luminous-armour", run.GearTarget?.GearId);

        run.FocusRoute("goblin-camp", "minthara");

        Assert.Null(run.GearTarget);
        Assert.Equal("goblin-camp", run.FocusedWalkthroughStepId);
        Assert.Equal("minthara", run.SelectedCheckpointId);
    }

    [Theory]
    [InlineData("Druid Grove", 1, 2)]
    [InlineData("Shattered Sanctum", 1, 5)]
    [InlineData("Moonrise Towers", 2, 3)]
    [InlineData("House of Hope", 3, 5)]
    [InlineData("Unmapped Place", 1, 18)]
    [InlineData("Unmapped Place", 9, 0)]
    public void RouteRankUsesTheOracleActOrdering(string region, int act, int expected)
    {
        Assert.Equal(expected, GearLogic.RouteRank(region, act));
    }

    [Theory]
    [InlineData("Sunlit Wetlands / Riverside Teahouse", GearRegionCluster.Wilderness)]
    [InlineData("Crèche Y'llek", GearRegionCluster.MountainPass)]
    [InlineData("Circus of the Last Days", GearRegionCluster.Rivington)]
    [InlineData("Unknown", GearRegionCluster.Other)]
    public void RegionClusterUsesTheSameCrossActTable(
        string region,
        GearRegionCluster expected)
    {
        Assert.Equal(expected, GearLogic.RegionCluster(region));
    }

    [Fact]
    public void MatchingStepsUsesContainmentInEitherDirectionAndRouteOrder()
    {
        var gear = Gear("Titanstring Bow", "Zhentarim Hideout / Risen Road");
        var steps = new[]
        {
            Step("road", 30, 2, "Risen Road", "The Risen Road"),
            Step("hideout", 20, 1, "Hideout", "Zhentarim Basement"),
            Step("grove", 10, 1, "Druid Grove", "Sanctum"),
        };

        var matches = GearLogic.MatchingSteps(gear, steps);

        Assert.Equal(["hideout", "road"], matches.Select(step => step.Id));
    }

    [Fact]
    public void PathRowsNeverInventStepsAndPreserveGateRequirementAndAcquireFallback()
    {
        var gear = Gear("Risky Ring", "Moonrise Towers") with
        {
            MinimumLevel = 7,
            Requirement = "Speak to Araj.",
            Acquire = "Buy from Araj Oblodra.",
        };
        var step = Step("moonrise", 50, 4, "Moonrise", "Main Floor");

        var rows = GearLogic.PathRows(
            gear,
            6,
            [step],
            new Dictionary<string, CheckpointDisposition>
            {
                [step.Id] = CheckpointDisposition.Completed,
            });

        Assert.Collection(
            rows,
            row =>
            {
                Assert.Equal(GearPathRowKind.LevelGate, row.Kind);
                Assert.Equal(7, row.RequiredLevel);
                Assert.Equal(6, row.PartyLevel);
            },
            row =>
            {
                Assert.Equal(GearPathRowKind.Step, row.Kind);
                Assert.Equal("moonrise", row.Step?.Id);
                Assert.True(row.Done);
            },
            row =>
            {
                Assert.Equal(GearPathRowKind.Info, row.Kind);
                Assert.Equal("Speak to Araj.", row.Text);
            },
            row =>
            {
                Assert.Equal(GearPathRowKind.Acquisition, row.Kind);
                Assert.Equal("Buy from Araj Oblodra.", row.Text);
            });

        var unmatched = GearLogic.PathRows(
            Gear("Hidden Item", "No Reviewed Region"),
            12,
            [step],
            new Dictionary<string, CheckpointDisposition>());
        var only = Assert.Single(unmatched);
        Assert.Equal(GearPathRowKind.Acquisition, only.Kind);
        Assert.Equal("Find it in the reviewed location.", only.Text);
    }

    [Fact]
    public void PickupsBucketByFirstMatchingPhaseAndKeepUnmatchedItems()
    {
        var walkthrough = new[]
        {
            Step("later-grove", 20, 2, "Druid Grove", "Inner Grove"),
            Step("first-grove", 10, 1, "Druid Grove", "Entrance"),
        };
        var grouped = GearLogic.PickupsByPhase(
            [
                new GearPickup(Gear("Idol", "Druid Grove"), "tav", "Tav"),
                new GearPickup(Gear("Unknown", "No Reviewed Region"), "gale", "Gale"),
            ],
            walkthrough);

        Assert.Equal("tav|idol", Assert.Single(grouped.ByPhase[1]).Id);
        Assert.Equal("gale|unknown", Assert.Single(grouped.Other).Id);
    }

    [Theory]
    [InlineData("Required", 0)]
    [InlineData("Defence", 5)]
    [InlineData("Endgame", 9)]
    [InlineData("Unknown", 99)]
    public void PriorityRankMatchesTheMacTable(string priority, int expected)
    {
        Assert.Equal(expected, GearLogic.PriorityRank(priority));
    }

    private static GearClaim Claim(
        string memberId,
        string build,
        long assignedAt,
        params string[] itemKeys) =>
        new(
            memberId,
            char.ToUpperInvariant(memberId[0]) + memberId[1..],
            build,
            DateTimeOffset.FromUnixTimeSeconds(assignedAt),
            itemKeys.ToHashSet(StringComparer.Ordinal));

    private static BuildGear Gear(string item, string region) =>
        new()
        {
            Item = item,
            Slot = "Melee",
            Priority = "Core",
            Act = 1,
            Region = region,
            Acquisition = "Find it in the reviewed location.",
            Why = "Test",
            Source = "Fixture",
        };

    private static WalkthroughStep Step(
        string id,
        int order,
        int phaseOrder,
        string region,
        string area) =>
        new()
        {
            Id = id,
            Order = order,
            Phase = $"Phase {phaseOrder}",
            PhaseOrder = phaseOrder,
            Title = id,
            Kind = "route",
            Importance = "minor",
            Region = region,
            Area = area,
            MinimumLevel = 1,
        };
}
