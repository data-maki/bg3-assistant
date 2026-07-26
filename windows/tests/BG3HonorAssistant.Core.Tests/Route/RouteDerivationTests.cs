using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class RouteDerivationTests
{
    [Fact]
    public void ActivityPlanLabelsSafeXpAndNamesTheCoreChallenge()
    {
        var safe = Checkpoint("safe", 1, 2, "minor");
        var major = Checkpoint("boss", 2, 4, "major");

        var plan = Assert.IsType<LevelActivityPlan>(
            RunSafety.ActivityPlan(
                [safe, major],
                new Dictionary<string, CheckpointDisposition>(),
                selectedId: null,
                partyLevel: 2));

        Assert.Equal("SAFE XP", plan.ActivityLabel);
        Assert.Equal(safe, plan.Recommendation);
        Assert.Equal([safe], plan.SafeXp);
        Assert.Equal(major, plan.CoreChallenge);
        Assert.Contains("builds XP toward Name boss (L4)", plan.GateAdvice);
    }

    [Fact]
    public void ActivityPlanDistinguishesLevelGateAndSelectedMainFight()
    {
        var safe = Checkpoint("safe", 1, 2, "minor");
        var major = Checkpoint("boss", 2, 4, "major");

        var gated = Assert.IsType<LevelActivityPlan>(
            RunSafety.ActivityPlan(
                [safe, major],
                new Dictionary<string, CheckpointDisposition>(),
                selectedId: null,
                partyLevel: 1));
        Assert.Equal("EARN XP FIRST", gated.ActivityLabel);
        Assert.Contains("needs L2", gated.GateAdvice);

        var selected = Assert.IsType<LevelActivityPlan>(
            RunSafety.ActivityPlan(
                [safe, major],
                new Dictionary<string, CheckpointDisposition>(),
                selectedId: major.Id,
                partyLevel: 4));
        Assert.Equal("MAIN FIGHT", selected.ActivityLabel);
    }

    [Theory]
    [InlineData("major_fight", false, false, StepEncounter.Fight)]
    [InlineData("major_fight", true, false, StepEncounter.FightAndTalk)]
    [InlineData("dialogue", false, false, StepEncounter.Talk)]
    [InlineData("dialogue", false, true, StepEncounter.FightAndTalk)]
    [InlineData("pickup", false, false, StepEncounter.Pickup)]
    [InlineData("gate", false, false, StepEncounter.Gate)]
    [InlineData("exploration", false, false, StepEncounter.Explore)]
    public void EncounterClassificationMatchesReviewedStepData(
        string kind,
        bool decision,
        bool incident,
        StepEncounter expected)
    {
        var step = Step(kind) with
        {
            Decision = decision
                ? new WalkthroughDecision(
                    "Choose",
                    new DecisionOption("Talk", [], []),
                    [],
                    false,
                    "guide_fact")
                : null,
            Incident = incident
                ? new IncidentProtocol
                {
                    Trigger = "Hostile",
                    Never = "Stay",
                    Escape = "Leave",
                    HonorDelta = "Risk",
                    Authority = "guide_fact",
                    SourceUrl = "https://example.invalid",
                }
                : null,
        };

        var actual = StepEncounterRules.Classify(step);

        Assert.Equal(expected, actual);
        Assert.Equal(
            expected == StepEncounter.FightAndTalk
                ? "Starts as a conversation — can turn into a fight"
                : null,
            actual.Hint());
    }

    [Fact]
    public void DependencyPresentationDistinguishesSequenceSkipAndChangedOutcome()
    {
        var prerequisite = Step("decision") with
        {
            Id = "choice",
            Title = "Choose the grove",
        };
        var dependent = Step("route") with
        {
            Id = "later",
            Phase = "Later",
            PhaseOrder = 2,
            Dependencies =
            [
                new WalkthroughDependency(
                    "choice",
                    "outcome_required",
                    "Follow the reviewed outcome.",
                    "Save the grove"),
            ],
        };
        WalkthroughStep[] route = [prerequisite, dependent];

        var pending = RunSafety.DependencyPresentation(
            dependent,
            route,
            new Dictionary<string, CheckpointDisposition>(),
            new Dictionary<string, string>(),
            prerequisite,
            route);
        var skipped = RunSafety.DependencyPresentation(
            dependent,
            route,
            new Dictionary<string, CheckpointDisposition>
            {
                ["choice"] = CheckpointDisposition.Skipped,
            },
            new Dictionary<string, string>(),
            prerequisite,
            route);
        var changed = RunSafety.DependencyPresentation(
            dependent,
            route,
            new Dictionary<string, CheckpointDisposition>
            {
                ["choice"] = CheckpointDisposition.Completed,
            },
            new Dictionary<string, string>
            {
                ["choice"] = "Raid the grove",
            },
            prerequisite,
            route);

        Assert.Equal(new("After Choose the grove", false), pending);
        Assert.Equal(new("Revisit Choose the grove", true), skipped);
        Assert.Equal(new("Route changed after Choose the grove", true), changed);
    }

    [Fact]
    public void DependencyPresentationLabelsLaterPhaseWithoutFalseAttention()
    {
        var current = Step("route");
        var later = Step("route") with
        {
            Id = "later",
            Phase = "Underdark",
            PhaseOrder = 2,
        };

        var presentation = RunSafety.DependencyPresentation(
            later,
            [current, later],
            new Dictionary<string, CheckpointDisposition>(),
            new Dictionary<string, string>(),
            current,
            [current, later]);

        Assert.Equal(new("Underdark", false), presentation);
    }

    private static RouteCheckpoint Checkpoint(
        string id,
        int order,
        int level,
        string importance) =>
        new()
        {
            Id = id,
            RouteOrder = order,
            Name = $"Name {id}",
            Area = "Area",
            Region = "Wilderness",
            MinimumLevel = level,
            Importance = importance,
            Danger = "medium",
        };

    private static WalkthroughStep Step(string kind) =>
        new()
        {
            Id = "step",
            Order = 1,
            Phase = "Opening",
            PhaseOrder = 1,
            Title = "Step",
            Kind = kind,
            Importance = "core",
            Region = "Wilderness",
            Area = "Area",
            MinimumLevel = 1,
        };
}
