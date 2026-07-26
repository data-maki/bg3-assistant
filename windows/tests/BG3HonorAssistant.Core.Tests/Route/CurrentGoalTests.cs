using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class CurrentGoalTests
{
    [Fact]
    public void SelectionUsesMacOraclePrecedence()
    {
        var checkpoint = Checkpoint();
        var step = Step(checkpoint.Id);
        var target = new GearTargetContext(
            Member(),
            new BuildGear
            {
                Item = "Risky Ring",
                Slot = "Ring",
                Priority = "Core",
                Act = 1,
                Region = "Moonrise",
                Acquisition = "Buy it",
                Why = "Advantage",
                Source = "https://example.invalid",
            });

        Assert.IsType<CurrentGoal.GearTargetGoal>(
            CurrentGoalRules.Select(target, true, step, checkpoint));
        Assert.IsType<CurrentGoal.LaterActGoal>(
            CurrentGoalRules.Select(null, false, step, checkpoint));
        Assert.IsType<CurrentGoal.WalkthroughStepGoal>(
            CurrentGoalRules.Select(null, true, step, checkpoint));
        Assert.IsType<CurrentGoal.CheckpointGoal>(
            CurrentGoalRules.Select(null, true, null, checkpoint));
        Assert.IsType<CurrentGoal.RouteCompleteGoal>(
            CurrentGoalRules.Select(null, true, null, null));
    }

    [Fact]
    public void LaterActUsesRequiredActTwoDataGapCopy()
    {
        var presentation = CurrentGoalRules.Present(
            new CurrentGoal.LaterActGoal(),
            selectedAct: 2,
            lowestPartyLevel: 7,
            routeHasConsequentialSkips: false,
            activeGuideLoaded: true,
            statusMessage: "ready",
            currentActTitle: "Shadow-Cursed Lands",
            route: [],
            currentCheckpoint: null);

        Assert.Equal(
            CurrentGoalRules.ActTwoUnavailableMessage,
            presentation.Avoid);
        Assert.Equal("Shadow-Cursed Lands", presentation.Title);
    }

    [Fact]
    public void StepPresentationUsesIncidentAndLinkedCheckpointDanger()
    {
        var checkpoint = Checkpoint();
        var step = Step(checkpoint.Id) with
        {
            Incident = new IncidentProtocol
            {
                Trigger = "Adds arrive",
                Never = "Do not stay.",
                Escape = "Leave.",
                HonorDelta = "Optional.",
                Authority = "guide_fact",
                SourceUrl = "https://example.invalid",
            },
        };

        var presentation = CurrentGoalRules.Present(
            new CurrentGoal.WalkthroughStepGoal(step),
            1,
            4,
            false,
            true,
            string.Empty,
            null,
            [checkpoint],
            checkpoint);

        Assert.Equal("Do not stay.", presentation.Avoid);
        Assert.Equal("extreme", presentation.Danger);
        Assert.True(new CurrentGoal.WalkthroughStepGoal(step).HasGuidedGoal);
    }

    private static PartyMember Member() =>
        new()
        {
            Id = "tav",
            Name = "Tav",
            Level = 4,
        };

    private static WalkthroughStep Step(string checkpointId) =>
        new()
        {
            Id = "walk-one",
            Order = 1,
            Phase = "Opening",
            PhaseOrder = 1,
            Title = "Take the safe route",
            Kind = "major_fight",
            Importance = "required",
            Region = "Wilderness",
            Area = "Road",
            MinimumLevel = 4,
            Avoid = "Avoid danger.",
            CheckpointId = checkpointId,
        };

    private static RouteCheckpoint Checkpoint() =>
        new()
        {
            Id = "fight-one",
            RouteOrder = 1,
            Name = "Fight",
            Area = "Road",
            Region = "Wilderness",
            MinimumLevel = 4,
            Importance = "major",
            Danger = "extreme",
            Advice = "Prepare.",
            FailureConditions = ["Do not wipe."],
        };
}
