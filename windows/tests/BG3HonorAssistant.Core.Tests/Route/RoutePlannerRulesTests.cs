using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class RoutePlannerRulesTests
{
    [Fact]
    public void AllFilterGroupsPhasesAndWeavesMappedAndOtherPickups()
    {
        var steps = new[]
        {
            Step("first", 1, 1, "Landing", "core"),
            Step("optional", 2, 1, "Landing", "optional"),
            Step("grove", 3, 2, "Grove", "core") with
            {
                Region = "Druid Grove",
                Area = "Druid Grove",
            },
        };
        var pickups = new[]
        {
            new GearPickup(Gear("Idol", "Druid Grove"), "tav", "Tav"),
            new GearPickup(Gear("Unknown", "No Reviewed Region"), "gale", "Gale"),
        };

        var result = RoutePlannerRules.Present(
            steps,
            new Dictionary<string, CheckpointDisposition>(),
            outcomes: null,
            RouteRevealPolicy.Everything,
            pickups,
            RouteContentFilter.All,
            steps[0],
            lowestPartyLevel: 1);

        Assert.Equal(0, result.ArchivedCount);
        Assert.Equal(3, result.TotalCount);
        Assert.Contains(
            result.Rows,
            row => row.Kind == RoutePlannerRowKind.Phase &&
                   row.Label == "GROVE");
        Assert.Contains(
            result.Rows,
            row => row.Kind == RoutePlannerRowKind.Gear &&
                   row.Label == "Idol");
        Assert.Contains(
            result.Rows,
            row => row.Kind == RoutePlannerRowKind.OtherGear &&
                   row.Label == "Unknown");
        Assert.Equal(
            "NOW",
            Assert.Single(result.Rows.Where(row => row.Step?.Id == "first")).Status);
    }

    [Fact]
    public void CoreFilterRemovesOptionalStepsAndAllGear()
    {
        var steps = new[]
        {
            Step("core", 1, 1, "Landing", "core"),
            Step("optional", 2, 1, "Landing", "optional"),
        };

        var result = RoutePlannerRules.Present(
            steps,
            new Dictionary<string, CheckpointDisposition>(),
            outcomes: null,
            RouteRevealPolicy.Everything,
            [new GearPickup(Gear("Sword", "Landing"), "tav", "Tav")],
            RouteContentFilter.Core,
            steps[0],
            lowestPartyLevel: 1);

        Assert.Single(result.Rows.Where(row => row.Step is not null));
        Assert.DoesNotContain(result.Rows, row => row.Pickup is not null);
    }

    [Fact]
    public void EquipmentFilterContainsNoRouteSteps()
    {
        var steps = new[] { Step("core", 1, 1, "Landing", "core") };

        var result = RoutePlannerRules.Present(
            steps,
            new Dictionary<string, CheckpointDisposition>(),
            outcomes: null,
            RouteRevealPolicy.Everything,
            [new GearPickup(Gear("Sword", "Landing"), "tav", "Tav")],
            RouteContentFilter.Equipment,
            steps[0],
            lowestPartyLevel: 1);

        Assert.DoesNotContain(result.Rows, row => row.Step is not null);
        Assert.Contains(result.Rows, row => row.Pickup is not null);
    }

    [Fact]
    public void NextThreeAndArchiveProgressPreserveDispositionSemantics()
    {
        var steps = Enumerable.Range(1, 6)
            .Select(index => Step($"step-{index}", index, index, $"P{index}", "core"))
            .ToArray();
        var progress = new Dictionary<string, CheckpointDisposition>
        {
            ["step-1"] = CheckpointDisposition.Completed,
            ["step-2"] = CheckpointDisposition.Skipped,
            ["step-3"] = CheckpointDisposition.CaughtUp,
        };

        var result = RoutePlannerRules.Present(
            steps,
            progress,
            outcomes: null,
            RouteRevealPolicy.NextThree,
            [],
            RouteContentFilter.All,
            steps[3],
            lowestPartyLevel: 1);

        Assert.True(result.SpoilerLight);
        Assert.Equal(3, result.ArchivedCount);
        Assert.Equal(0.5D, result.Progress);
        Assert.Equal(3, result.Rows.Count(row => row.Step is not null));
        Assert.Equal(
            [
                CheckpointDisposition.Completed,
                CheckpointDisposition.Skipped,
                CheckpointDisposition.CaughtUp,
            ],
            result.Archived.Select(row => row.Disposition));
    }

    private static WalkthroughStep Step(
        string id,
        int order,
        int phaseOrder,
        string phase,
        string importance) =>
        new()
        {
            Id = id,
            Order = order,
            Phase = phase,
            PhaseOrder = phaseOrder,
            Title = id,
            Kind = "exploration",
            Importance = importance,
            Region = phase,
            Area = phase,
            MinimumLevel = 1,
        };

    private static BuildGear Gear(string item, string region) =>
        new()
        {
            Item = item,
            Slot = "Melee",
            Priority = "Core",
            Act = 1,
            Region = region,
            Acquisition = "Take it",
            Why = "Useful",
            Source = "fixture",
        };
}
