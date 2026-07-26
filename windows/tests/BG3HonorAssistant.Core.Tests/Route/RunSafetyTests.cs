using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class RunSafetyTests
{
    [Fact]
    public void WarningOnlyDependencyNeverBlocks()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "warning_only")]);

        var blockers = RunSafety.DependencyBlockers(
            target,
            [Step("a", 1), target],
            new Dictionary<string, CheckpointDisposition>());

        Assert.Empty(blockers);
    }

    [Fact]
    public void CompletionRequiredBlocksUntilCompleted()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "completion_required")]);
        WalkthroughStep[] walkthrough = [Step("a", 1), target];

        Assert.Equal(
            ["reason"],
            RunSafety.DependencyBlockers(
                target,
                walkthrough,
                new Dictionary<string, CheckpointDisposition>()));
        Assert.Empty(RunSafety.DependencyBlockers(
            target,
            walkthrough,
            new Dictionary<string, CheckpointDisposition>
            {
                ["a"] = CheckpointDisposition.Completed,
            }));
    }

    [Fact]
    public void SkippedCompletionDependencyAsksForRevisit()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "completion_required")]);

        var blockers = RunSafety.DependencyBlockers(
            target,
            [Step("a", 1), target],
            new Dictionary<string, CheckpointDisposition>
            {
                ["a"] = CheckpointDisposition.Skipped,
            });

        Assert.Equal(["Revisit Title a — reason"], blockers);
    }

    [Fact]
    public void OutcomeRequiredNeedsCompletionAndMatchingOutcome()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "outcome_required", requiredOutcome: "Spared")]);
        WalkthroughStep[] walkthrough = [Step("a", 1), target];
        var completed = new Dictionary<string, CheckpointDisposition>
        {
            ["a"] = CheckpointDisposition.Completed,
        };

        Assert.NotEmpty(RunSafety.DependencyBlockers(
            target,
            walkthrough,
            completed,
            new Dictionary<string, string> { ["a"] = "Killed" }));
        Assert.Empty(RunSafety.DependencyBlockers(
            target,
            walkthrough,
            completed,
            new Dictionary<string, string> { ["a"] = "Spared" }));
    }

    [Fact]
    public void DefaultDependencyKindAcceptsAnyResolution()
    {
        var target = Step("b", 2, dependencies: [Dependency("a", "soft")]);
        WalkthroughStep[] walkthrough = [Step("a", 1), target];

        Assert.NotEmpty(RunSafety.DependencyBlockers(
            target,
            walkthrough,
            new Dictionary<string, CheckpointDisposition>()));
        Assert.Empty(RunSafety.DependencyBlockers(
            target,
            walkthrough,
            new Dictionary<string, CheckpointDisposition>
            {
                ["a"] = CheckpointDisposition.Skipped,
            }));
    }

    [Fact]
    public void ActTwoBlockersReportSkippedAndUnresolvedMajors()
    {
        RouteCheckpoint[] route =
        [
            Checkpoint("done", 1, importance: "major"),
            Checkpoint(
                "skipped",
                2,
                importance: "major",
                irreversibleWarnings: ["Point of no return"]),
            Checkpoint("pendingMinor", 3),
            Checkpoint("pendingWarned", 4, irreversibleWarnings: ["Warned"]),
        ];

        var blockers = RunSafety.ActTwoBlockers(
            route,
            new Dictionary<string, CheckpointDisposition>
            {
                ["done"] = CheckpointDisposition.Completed,
                ["skipped"] = CheckpointDisposition.Skipped,
            });

        Assert.Equal(
            [
                "Skipped — Name skipped: Point of no return",
                "Unresolved — Name pendingWarned: Warned",
            ],
            blockers);
    }

    [Fact]
    public void CaughtUpSatisfiesCompletionRequiredDependency()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "completion_required")]);

        var blockers = RunSafety.DependencyBlockers(
            target,
            [Step("a", 1), target],
            new Dictionary<string, CheckpointDisposition>
            {
                ["a"] = CheckpointDisposition.CaughtUp,
            });

        Assert.Empty(blockers);
    }

    [Fact]
    public void CaughtUpSatisfiesOutcomeRequiredWithoutRecordedOutcome()
    {
        var target = Step(
            "b",
            2,
            dependencies: [Dependency("a", "outcome_required", requiredOutcome: "Spared")]);

        var blockers = RunSafety.DependencyBlockers(
            target,
            [Step("a", 1), target],
            new Dictionary<string, CheckpointDisposition>
            {
                ["a"] = CheckpointDisposition.CaughtUp,
            });

        Assert.Empty(blockers);
    }

    [Fact]
    public void RouteConsequencesIgnoreCaughtUpCheckpoints()
    {
        RouteCheckpoint[] route =
        [
            Checkpoint(
                "adopted",
                1,
                importance: "major",
                irreversibleWarnings: ["Point of no return"]),
            Checkpoint("open", 2, importance: "major"),
        ];

        var consequences = RunSafety.RouteConsequences(
            route,
            new Dictionary<string, CheckpointDisposition>
            {
                ["adopted"] = CheckpointDisposition.CaughtUp,
            });

        Assert.Equal(["Unresolved — Name open: major checkpoint unresolved"], consequences);
    }

    [Fact]
    public void ReadinessBlocksWhenNoActivePartyIsRecorded()
    {
        var fight = Checkpoint("boss", 1, minimumLevel: 10);

        var readiness = Assess(fight, activeParty: []);

        Assert.Equal("blocked", readiness.Status);
        Assert.Contains(readiness.Blockers, blocker => blocker.Contains("No active party"));
    }

    [Fact]
    public void ReadinessUsesLowestPartyLevelAndCheckedPreparation()
    {
        var fight = Checkpoint(
            "boss",
            1,
            minimumLevel: 10,
            preparation: ["Buy potions"]);

        var ready = Assess(
            fight,
            activeParty: [Member("tav", 10)],
            checkedPreparation: new HashSet<string> { "Buy potions" });

        Assert.Equal("ready", ready.Status);
        Assert.Empty(ready.Blockers);
        Assert.Empty(ready.Warnings);

        var underleveled = Assess(fight, activeParty: [Member("tav", 8)]);
        Assert.Equal("blocked", underleveled.Status);
        Assert.Contains(
            underleveled.Blockers,
            blocker => blocker.Contains(
                "Lowest party member is level 8; guide minimum is level 10.",
                StringComparison.Ordinal));
    }

    [Fact]
    public void ReadinessBlocksSkippedRequiredRoutePrerequisite()
    {
        var gate = Checkpoint("gate", 1);
        var fight = Checkpoint("boss", 2, prerequisites: ["gate"]);
        var owner = Step(
            "walk-boss",
            2,
            dependencies: [Dependency("walk-gate", "completion_required")]) with
        {
            CheckpointId = "boss",
        };

        var readiness = RunSafety.AssessReadiness(
            fight,
            [gate, fight],
            [Step("walk-gate", 1), owner],
            [Member("tav", 12)],
            new HashSet<string>(),
            new HashSet<string>(),
            new Dictionary<string, CheckpointDisposition>
            {
                ["walk-gate"] = CheckpointDisposition.Skipped,
            },
            new Dictionary<string, string>(),
            []);

        Assert.Equal("blocked", readiness.Status);
        Assert.Contains(
            readiness.Blockers,
            blocker => blocker.Contains(
                "Unresolved reviewed route sequence: Name gate",
                StringComparison.Ordinal));
        Assert.Contains(readiness.Blockers, blocker => blocker.Contains("Revisit"));
    }

    [Fact]
    public void ReadinessWarnsOnUncheckedPreparationAndUnrecordedCapability()
    {
        var fight = Checkpoint(
            "boss",
            1,
            advice: "Open with silence to shut down casters.",
            preparation: ["Prepare Silence"]);

        var readiness = Assess(fight, activeParty: [Member("tav", 5)]);

        Assert.Equal("caution", readiness.Status);
        Assert.Contains(
            readiness.Warnings,
            warning => warning.Contains(
                "Preparation not confirmed: Prepare Silence",
                StringComparison.Ordinal));
        Assert.Contains(
            readiness.Warnings,
            warning => warning.Contains(
                "Party capability not recorded: silence",
                StringComparison.Ordinal));
        Assert.Contains("Prepare Silence", readiness.NextActions);

        var covered = Assess(
            fight,
            activeParty: [Member("tav", 5, preparedTags: ["Silence ritual"])],
            checkedPreparation: new HashSet<string> { "Prepare Silence" });
        Assert.DoesNotContain(
            covered.Warnings,
            warning => warning.Contains("capability", StringComparison.Ordinal));
    }

    [Fact]
    public void ReadinessDangerStatusFromExtremeDangerOrIrreversibleWarnings()
    {
        var extreme = Checkpoint("boss", 1, danger: "extreme");
        Assert.Equal("danger", Assess(extreme, [Member("tav", 5)]).Status);

        var irreversible = Checkpoint(
            "gate",
            1,
            irreversibleWarnings: ["Point of no return"]);
        var readiness = Assess(irreversible, [Member("tav", 5)]);
        Assert.Equal("danger", readiness.Status);
        Assert.Contains("Point of no return", readiness.Warnings);
    }

    private static WalkthroughStep Step(
        string id,
        int order,
        int phaseOrder = 1,
        string kind = "exploration",
        int minimumLevel = 1,
        IReadOnlyList<WalkthroughDependency>? dependencies = null)
    {
        return new WalkthroughStep
        {
            Id = id,
            Order = order,
            Phase = $"Phase {phaseOrder}",
            PhaseOrder = phaseOrder,
            Title = $"Title {id}",
            Kind = kind,
            Importance = "core",
            Region = "Wilderness",
            Area = "Area",
            MinimumLevel = minimumLevel,
            Dependencies = dependencies ?? [],
            Authority = "guide_fact",
        };
    }

    private static WalkthroughDependency Dependency(
        string stepId,
        string kind,
        string reason = "reason",
        string? requiredOutcome = null)
    {
        return new WalkthroughDependency(stepId, kind, reason, requiredOutcome);
    }

    private static RouteCheckpoint Checkpoint(
        string id,
        int routeOrder,
        string region = "Wilderness",
        int minimumLevel = 1,
        string importance = "minor",
        string danger = "medium",
        string advice = "",
        IReadOnlyList<string>? preparation = null,
        IReadOnlyList<string>? irreversibleWarnings = null,
        IReadOnlyList<string>? prerequisites = null)
    {
        return new RouteCheckpoint
        {
            Id = id,
            RouteOrder = routeOrder,
            Name = $"Name {id}",
            Area = "Area",
            Region = region,
            X = 0,
            Y = 0,
            MinimumLevel = minimumLevel,
            Importance = importance,
            Danger = danger,
            Advice = advice,
            Preparation = preparation ?? [],
            IrreversibleWarnings = irreversibleWarnings ?? [],
            Prerequisites = prerequisites ?? [],
            Source = new GuideSource("Route", 1, string.Empty),
        };
    }

    private static PartyMember Member(
        string id,
        int level,
        string? buildId = null,
        IReadOnlyList<string>? preparedTags = null)
    {
        return new PartyMember
        {
            Id = id,
            Name = $"Name {id}",
            Level = level,
            BuildId = buildId,
            PreparedTags = preparedTags ?? [],
        };
    }

    private static ReadinessResponse Assess(
        RouteCheckpoint checkpoint,
        IReadOnlyList<PartyMember> activeParty,
        IReadOnlyList<RouteCheckpoint>? route = null,
        IReadOnlyList<WalkthroughStep>? walkthrough = null,
        IReadOnlySet<string>? completedIds = null,
        IReadOnlySet<string>? checkedPreparation = null,
        IReadOnlyDictionary<string, CheckpointDisposition>? walkthroughProgress = null,
        IReadOnlyDictionary<string, string>? walkthroughOutcomes = null)
    {
        return RunSafety.AssessReadiness(
            checkpoint,
            route ?? [checkpoint],
            walkthrough ?? [],
            activeParty,
            completedIds ?? new HashSet<string>(),
            checkedPreparation ?? new HashSet<string>(),
            walkthroughProgress ?? new Dictionary<string, CheckpointDisposition>(),
            walkthroughOutcomes ?? new Dictionary<string, string>(),
            []);
    }
}
