using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class RunProgressRulesTests
{
    [Fact]
    public void VisibleAndArchivedStepsRespectRevealPolicy()
    {
        var steps = Enumerable.Range(1, 5)
            .Select(index => Step($"s{index}", index, index))
            .ToList();
        var progress = new Dictionary<string, CheckpointDisposition>
        {
            ["s1"] = CheckpointDisposition.Completed,
        };

        Assert.Equal(
            ["s2", "s3", "s4"],
            RunProgressRules.VisibleSteps(
                    steps,
                    progress,
                    RouteRevealPolicy.NextThree)
                .Select(step => step.Id));
        Assert.Equal(
            ["s1"],
            RunProgressRules.ArchivedSteps(steps, progress).Select(step => step.Id));
    }

    [Fact]
    public void SaferAlternativePrefersSameRegionThenLowestLevelAndOrder()
    {
        var current = Step("current", 10, 2) with
        {
            Region = "Underdark",
            MinimumLevel = 5,
        };
        var localLater = Step("local-later", 30, 3) with
        {
            Region = "Underdark",
            MinimumLevel = 3,
        };
        var localFirst = Step("local-first", 20, 3) with
        {
            Region = "Underdark",
            MinimumLevel = 3,
        };
        var samePhase = Step("same-phase", 1, 2) with
        {
            Region = "Wilderness",
            MinimumLevel = 1,
        };

        Assert.Equal(
            "local-first",
            RunProgressRules.SaferAlternative(
                current,
                [current, localLater, localFirst, samePhase],
                null,
                3)?.Id);
    }

    [Fact]
    public void DispositionMovesFocusAndPendingRevisitClearsOutcome()
    {
        var run = new HonorRun
        {
            SelectedAct = 1,
            FocusedWalkthroughStepId = "choice",
            SelectedCheckpointId = "fight",
            WalkthroughOutcomes = new() { ["choice"] = "Saved" },
        };
        var step = Step("choice", 1, 1) with { CheckpointId = "fight" };

        Assert.True(
            RunProgressRules.SetWalkthroughDisposition(
                run,
                step,
                CheckpointDisposition.Completed));
        Assert.Null(run.FocusedWalkthroughStepId);
        Assert.Null(run.SelectedCheckpointId);

        Assert.True(
            RunProgressRules.SetWalkthroughDisposition(
                run,
                step,
                CheckpointDisposition.Pending));
        Assert.Equal("choice", run.FocusedWalkthroughStepId);
        Assert.Equal("fight", run.SelectedCheckpointId);
        Assert.False(run.WalkthroughOutcomes.ContainsKey("choice"));
    }

    [Fact]
    public void LockedActRejectsDispositionAndOutcomeMutation()
    {
        var run = new HonorRun
        {
            SelectedAct = 3,
            FinalActRecord = new ActTransitionRecord(
                3,
                3,
                new Dictionary<string, ActGearReviewStatus>(),
                0,
                DateTimeOffset.UnixEpoch),
        };
        var step = Step("past", 1, 1);

        Assert.False(
            RunProgressRules.SetWalkthroughDisposition(
                run,
                step,
                CheckpointDisposition.Completed));
        Assert.False(RunProgressRules.ResolveOutcome(run, step, "Choice"));
        Assert.Null(run.WalkthroughProgress);
        Assert.Null(run.WalkthroughOutcomes);
    }

    [Fact]
    public void CheckpointDispositionUpdatesChecklistRecordAndOwnedStep()
    {
        var run = new HonorRun { SelectedAct = 1 };
        var checkpoint = Checkpoint("fight", warnings: ["Irreversible"]);
        var step = Step("step", 1, 1) with { CheckpointId = checkpoint.Id };
        var now = DateTimeOffset.FromUnixTimeSeconds(7);

        Assert.True(
            RunProgressRules.SetCheckpointDisposition(
                run,
                checkpoint,
                [step],
                CheckpointDisposition.Skipped,
                "Come back later",
                now));

        Assert.Equal("Come back later", run.Progress[checkpoint.Id].SkipNote);
        Assert.Equal(now, run.Progress[checkpoint.Id].UpdatedAt);
        Assert.Equal(
            CheckpointDisposition.Skipped,
            run.WalkthroughProgress![step.Id]);
        var request = RunProgressRules.RequestDisposition(
            checkpoint,
            CheckpointDisposition.Skipped);
        Assert.True(request.RequiresConfirmation);
        Assert.Contains("irreversible", request.ConfirmationMessage);
    }

    [Fact]
    public void ConsequentialSkipAndMuteAreExplicit()
    {
        var run = new HonorRun();
        var required = Step("required", 1, 1) with { Importance = "required" };
        var optional = Step("optional", 2, 1) with { Importance = "optional" };
        var progress = new Dictionary<string, CheckpointDisposition>
        {
            [required.Id] = CheckpointDisposition.Skipped,
            [optional.Id] = CheckpointDisposition.Skipped,
        };

        Assert.True(
            RunProgressRules.RouteHasConsequentialSkips(
                [required, optional],
                progress));
        Assert.True(RunProgressRules.ToggleMute(run, "fight"));
        Assert.Contains("fight", run.MutedCheckpointIds!);
        Assert.False(RunProgressRules.ToggleMute(run, "fight"));
        Assert.DoesNotContain("fight", run.MutedCheckpointIds!);
    }

    [Fact]
    public void IncidentFallbackUsesOnlyReviewedCheckpointFacts()
    {
        var checkpoint = Checkpoint("fight", warnings: []) with
        {
            FailureConditions = ["Boss starts ritual", "Party is trapped"],
            Preparation = ["Potion", "Mobility", "Silence", "Extra"],
            Advice = "Stay spread out.",
            LegendaryAction = "Retaliates on first hit.",
            Source = new GuideSource("guide", 1, "https://example.invalid/source"),
        };
        var step = Step("step", 1, 1) with
        {
            CheckpointId = checkpoint.Id,
            Avoid = "Never group up.",
        };

        var incident = Assert.IsType<IncidentProtocol>(
            RunProgressRules.IncidentProtocol(step, [checkpoint]));

        Assert.Equal("Boss starts ritual", incident.Trigger);
        Assert.Equal(["Potion", "Mobility", "Silence"], incident.SafeActions);
        Assert.Equal("Never group up.", incident.Never);
        Assert.Equal("Retaliates on first hit.", incident.HonorDelta);
        Assert.Equal("guide_fact", incident.Authority);
    }

    private static WalkthroughStep Step(string id, int order, int phase) =>
        new()
        {
            Id = id,
            Order = order,
            Phase = $"Phase {phase}",
            PhaseOrder = phase,
            Title = id,
            Kind = "route",
            Importance = "minor",
            Region = "Wilderness",
            Area = "Area",
            MinimumLevel = 1,
        };

    private static RouteCheckpoint Checkpoint(
        string id,
        IReadOnlyList<string> warnings) =>
        new()
        {
            Id = id,
            RouteOrder = 1,
            Name = id,
            Area = "Area",
            Region = "Wilderness",
            MinimumLevel = 1,
            Importance = "major",
            Danger = "high",
            IrreversibleWarnings = warnings,
        };
}
