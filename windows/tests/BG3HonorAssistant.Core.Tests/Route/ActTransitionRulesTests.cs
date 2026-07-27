using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;

namespace BG3HonorAssistant.Core.Tests.Route;

public sealed class ActTransitionRulesTests
{
    [Theory]
    [InlineData(3, true, true, true, 0, "Act 3 is the final act.")]
    [InlineData(1, false, true, true, 0, "The next act database is not installed.")]
    [InlineData(
        1,
        true,
        false,
        true,
        0,
        "Act 1 guide data must finish loading before this gate can unlock.")]
    [InlineData(
        2,
        true,
        true,
        false,
        0,
        "Act 2 route coverage must be reviewed before this gate can unlock.")]
    [InlineData(1, true, true, true, 1, "Review 1 equipment item first.")]
    [InlineData(1, true, true, true, 2, "Review 2 equipment items first.")]
    [InlineData(1, true, true, true, 0, null)]
    public void TransitionGateMatchesOraclePrecedence(
        int selectedAct,
        bool nextActGuideExists,
        bool guideLoaded,
        bool routeAvailable,
        int unresolvedGear,
        string? expected)
    {
        Assert.Equal(
            expected,
            ActTransitionRules.TransitionBlockedReason(
                selectedAct,
                nextActGuideExists,
                guideLoaded,
                routeAvailable,
                unresolvedGear));
    }

    [Fact]
    public void ReviewStatusPrefersLockedLedgerThenEquippedThenEditableReview()
    {
        var gear = Gear("Caustic Band");
        var run = new HonorRun
        {
            SelectedAct = 2,
            ActTransitions =
            [
                new ActTransitionRecord(
                    1,
                    2,
                    new Dictionary<string, ActGearReviewStatus>
                    {
                        [gear.ItemKey] = ActGearReviewStatus.Missed,
                    },
                    0,
                    DateTimeOffset.UnixEpoch),
            ],
            EquippedByMember = new Dictionary<string, HashSet<string>>
            {
                ["tav"] = [gear.ItemKey],
            },
            ActGearReview = new Dictionary<int, Dictionary<string, ActGearReviewStatus>>
            {
                [2] = new()
                {
                    [gear.ItemKey] = ActGearReviewStatus.Missed,
                },
            },
        };

        Assert.Equal(
            ActGearReviewStatus.Missed,
            ActTransitionRules.ReviewStatus(run, gear, 1));
        Assert.Equal(
            ActGearReviewStatus.Obtained,
            ActTransitionRules.ReviewStatus(run, gear, 2));
        Assert.False(
            ActTransitionRules.TrySetReview(
                run,
                gear,
                1,
                ActGearReviewStatus.Obtained));
        Assert.True(
            ActTransitionRules.TrySetReview(
                run,
                gear,
                2,
                ActGearReviewStatus.Missed));
        Assert.Null(run.EquipmentOwnerId(gear.ItemKey));
        Assert.Equal(
            ActGearReviewStatus.Missed,
            ActTransitionRules.ReviewStatus(run, gear, 2));
    }

    [Fact]
    public void LegacyLockedActReconstructsKnownGearAndKeepsRouteOrder()
    {
        var late = Gear("Late", "Grymforge");
        var run = new HonorRun
        {
            SelectedAct = 2,
            ActTransitions =
            [
                new ActTransitionRecord(
                    1,
                    2,
                    new Dictionary<string, ActGearReviewStatus>
                    {
                        ["late"] = ActGearReviewStatus.Obtained,
                        ["idol"] = ActGearReviewStatus.Missed,
                        ["unknown"] = ActGearReviewStatus.Missed,
                    },
                    0,
                    DateTimeOffset.UnixEpoch),
            ],
        };
        var catalog = new[]
        {
            new ItemSummary
            {
                ItemKey = "idol",
                Name = "Idol",
                Slot = "Melee",
                Act = 1,
                Region = "Druid Grove",
                Acquisition = "Steal it.",
                Wiki = "https://example.invalid/idol",
            },
        };

        var locked = ActTransitionRules.ActGear(run, 1, [late], catalog);

        Assert.Equal(["Idol", "Late"], locked.Select(item => item.Item));
        Assert.Equal("Chosen", locked[0].Priority);
        Assert.DoesNotContain(locked, item => item.ItemKey == "unknown");
    }

    [Fact]
    public void HistoricConsequencesUseRecordedCountWithoutInventingDetails()
    {
        var run = new HonorRun
        {
            SelectedAct = 2,
            ActTransitions =
            [
                new ActTransitionRecord(
                    1,
                    2,
                    new Dictionary<string, ActGearReviewStatus>(),
                    2,
                    DateTimeOffset.UnixEpoch),
            ],
        };

        var result = ActTransitionRules.RouteConsequences(
            run,
            1,
            loadedGuideAct: 2,
            loadedRouteAvailable: true,
            route: [],
            dispositions: new Dictionary<string, CheckpointDisposition>());

        Assert.Equal(
            ["Advanced with 2 unresolved route consequences."],
            result);
    }

    [Fact]
    public void AdvanceRequiresExplicitConsequenceConsentAndLocksCompleteSnapshot()
    {
        var gear = Gear("Caustic Band", "Druid Grove");
        var run = new HonorRun
        {
            SelectedAct = 1,
            SelectedCheckpointId = "checkpoint",
            FocusedWalkthroughStepId = "step",
            ActGearReview = new Dictionary<int, Dictionary<string, ActGearReviewStatus>>
            {
                [1] = new()
                {
                    [gear.ItemKey] = ActGearReviewStatus.Missed,
                },
            },
        };
        var destination = ActGuide(2, "Shadow-Cursed Lands");
        var now = DateTimeOffset.FromUnixTimeSeconds(42);

        Assert.False(
            ActTransitionRules.TryAdvance(
                run,
                destination,
                activeGuideLoaded: true,
                activeRouteAvailable: true,
                currentActGear: [gear],
                routeConsequences: ["Unresolved — Grove"],
                acceptingRouteConsequences: false,
                advancedAt: now));

        Assert.True(
            ActTransitionRules.TryAdvance(
                run,
                destination,
                activeGuideLoaded: true,
                activeRouteAvailable: true,
                currentActGear: [gear],
                routeConsequences: ["Unresolved — Grove"],
                acceptingRouteConsequences: true,
                advancedAt: now));

        Assert.Equal(2, run.SelectedAct);
        Assert.Null(run.SelectedCheckpointId);
        Assert.Null(run.FocusedWalkthroughStepId);
        Assert.Equal("Shadow-Cursed Lands", run.MapRegion);
        var record = Assert.Single(run.ActTransitions!);
        Assert.Equal(1, record.FromAct);
        Assert.Equal(2, record.ToAct);
        Assert.Equal(1, record.UnresolvedRouteCount);
        Assert.Equal(now, record.AdvancedAt);
        Assert.Equal(ActGearReviewStatus.Missed, record.GearReview[gear.ItemKey]);
        Assert.Equal(gear, Assert.Single(record.Gear!));
        Assert.True(run.ActLedgerIsLocked(1));
    }

    [Theory]
    [InlineData(2, false, true, 0, 0, "Only Act 3 can complete the run.")]
    [InlineData(3, false, true, 0, 0, "Act 3 guide data must finish loading first.")]
    [InlineData(3, true, true, 1, 0, "Resolve or deliberately skip 1 route step first.")]
    [InlineData(3, true, true, 2, 0, "Resolve or deliberately skip 2 route steps first.")]
    [InlineData(3, true, true, 0, 2, "Review 2 equipment items first.")]
    [InlineData(3, true, true, 0, 0, null)]
    public void FinalGateMatchesOraclePrecedence(
        int selectedAct,
        bool guideLoaded,
        bool routeAvailable,
        int activeSteps,
        int unresolvedGear,
        string? expected)
    {
        var run = new HonorRun { SelectedAct = selectedAct };

        Assert.Equal(
            expected,
            ActTransitionRules.FinalActBlockedReason(
                run,
                guideLoaded,
                routeAvailable,
                activeSteps,
                unresolvedGear));
    }

    [Fact]
    public void FinalizeActThreeRequiresReviewAndLocksLedger()
    {
        var gear = Gear("Balduran's Giantslayer", "Lower City") with { Act = 3 };
        var run = new HonorRun
        {
            SelectedAct = 3,
            ActGearReview = new Dictionary<int, Dictionary<string, ActGearReviewStatus>>
            {
                [3] = new()
                {
                    [gear.ItemKey] = ActGearReviewStatus.Obtained,
                },
            },
        };
        var now = DateTimeOffset.FromUnixTimeSeconds(99);

        Assert.True(
            ActTransitionRules.TryFinalizeActThree(
                run,
                activeGuideLoaded: true,
                activeRouteAvailable: true,
                activeWalkthroughStepCount: 0,
                currentActGear: [gear],
                routeConsequences: [],
                acceptingRouteConsequences: false,
                advancedAt: now));

        Assert.NotNull(run.FinalActRecord);
        Assert.Equal(now, run.FinalActRecord!.AdvancedAt);
        Assert.True(run.ActLedgerIsLocked(3));
        Assert.False(
            ActTransitionRules.TrySetReview(
                run,
                gear,
                3,
                ActGearReviewStatus.Missed));
        Assert.False(
            ActTransitionRules.TryFinalizeActThree(
                run,
                true,
                true,
                0,
                [gear],
                [],
                false,
                now.AddSeconds(1)));
    }

    private static BuildGear Gear(string item, string region = "Anywhere") =>
        new()
        {
            Item = item,
            Slot = "Melee",
            Priority = "Core",
            Act = 1,
            Region = region,
            Acquisition = "Fixture acquisition",
            Why = "Fixture why",
            Source = "Fixture",
        };

    private static ActGuideSummary ActGuide(int act, string title) =>
        new()
        {
            Act = act,
            Title = title,
            RouteAvailable = act != 2,
            LocalMapAvailable = false,
            MapName = $"Act {act}",
            MapUrl = "https://example.invalid/map",
            EquipmentFile = $"act-{act}.tsv",
            CoordinateSystem = "BG3",
            CoordinateNote = "Fixture",
            EquipmentCount = 0,
        };
}
