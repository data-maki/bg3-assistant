using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Route;

public static class ActTransitionRules
{
    public static IReadOnlyList<BuildGear> ActGear(
        HonorRun run,
        int act,
        IReadOnlyList<BuildGear> plannedGear,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        var locked = run.LockedActRecord(act);
        if (locked?.Gear is not null)
        {
            return SortActGear(locked.Gear);
        }

        if (locked is not null)
        {
            var current = plannedGear
                .GroupBy(gear => gear.ItemKey, StringComparer.Ordinal)
                .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
            var legacy = locked.GearReview.Keys
                .Select(
                    key =>
                    {
                        if (current.TryGetValue(key, out var gear))
                        {
                            return gear;
                        }

                        var item = itemCatalog.FirstOrDefault(item => item.ItemKey == key);
                        return item is null ? null : SyntheticGear(item);
                    })
                .Where(gear => gear is not null)
                .Cast<BuildGear>()
                .ToList();
            return SortActGear(legacy);
        }

        return SortActGear(plannedGear);
    }

    public static IReadOnlyList<BuildGear> SortActGear(IReadOnlyList<BuildGear> gear) =>
        gear.OrderBy(item => GearLogic.RouteRank(item.Region, item.Act))
            .ThenBy(item => item.Region, StringComparer.Ordinal)
            .ThenBy(item => item.Item, StringComparer.Ordinal)
            .ToList();

    public static BuildGear SyntheticGear(ItemSummary item) =>
        new()
        {
            Item = item.Name,
            Slot = item.Slot,
            Priority = "Chosen",
            Act = item.Act,
            Region = item.Region,
            Acquisition = item.Acquisition,
            Why = "Player-chosen replacement pick",
            Source = item.Wiki,
            MapObjective = item.MapObjective,
            Effect = item.Effect,
            Acquire = item.Acquire,
            Wiki = item.Wiki,
            Icon = item.Icon,
            GameX = item.GameX,
            GameY = item.GameY,
        };

    public static ActGearReviewStatus? ReviewStatus(
        HonorRun run,
        BuildGear gear,
        int act)
    {
        var locked = run.LockedActGearReviewStatus(gear.ItemKey, act);
        if (locked is not null)
        {
            return locked;
        }

        if (run.EquipmentOwnerId(gear.ItemKey) is not null)
        {
            return ActGearReviewStatus.Obtained;
        }

        return run.ActGearReview is not null &&
               run.ActGearReview.TryGetValue(act, out var review) &&
               review.TryGetValue(gear.ItemKey, out var status)
            ? status
            : null;
    }

    public static bool TrySetReview(
        HonorRun run,
        BuildGear gear,
        int act,
        ActGearReviewStatus status)
    {
        if (run.ActLedgerIsLocked(act))
        {
            return false;
        }

        run.ActGearReview ??= [];
        if (!run.ActGearReview.TryGetValue(act, out var review))
        {
            review = [];
            run.ActGearReview[act] = review;
        }

        review[gear.ItemKey] = status;
        return true;
    }

    public static IReadOnlyList<BuildGear> UnresolvedGear(
        HonorRun run,
        int act,
        IReadOnlyList<BuildGear> gear) =>
        gear.Where(item => ReviewStatus(run, item, act) is null).ToList();

    public static IReadOnlyList<BuildGear> ReviewedGear(
        HonorRun run,
        int act,
        IReadOnlyList<BuildGear> gear) =>
        gear.Where(item => ReviewStatus(run, item, act) is not null).ToList();

    public static IReadOnlyList<string> RouteConsequences(
        HonorRun run,
        int act,
        int? loadedGuideAct,
        bool loadedRouteAvailable,
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions)
    {
        if (act == (run.SelectedAct ?? 1) &&
            loadedGuideAct == act &&
            loadedRouteAvailable)
        {
            return act == 1
                ? RunSafety.ActTwoBlockers(route, dispositions)
                : RunSafety.RouteConsequences(route, dispositions);
        }

        var count = run.ActTransitions?
            .FirstOrDefault(transition => transition.FromAct == act)?
            .UnresolvedRouteCount;
        return count is > 0
            ?
            [
                $"Advanced with {count} unresolved route consequence" +
                $"{(count == 1 ? string.Empty : "s")}.",
            ]
            : [];
    }

    public static int RouteConsequenceCount(
        HonorRun run,
        int act,
        int? loadedGuideAct,
        bool loadedRouteAvailable,
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions)
    {
        if (act == (run.SelectedAct ?? 1) &&
            loadedGuideAct == act &&
            loadedRouteAvailable)
        {
            return RouteConsequences(
                    run,
                    act,
                    loadedGuideAct,
                    loadedRouteAvailable,
                    route,
                    dispositions)
                .Count;
        }

        return run.LockedActRecord(act)?.UnresolvedRouteCount ?? 0;
    }

    public static string? TransitionBlockedReason(
        int selectedAct,
        bool nextActGuideExists,
        bool activeGuideLoaded,
        bool activeRouteAvailable,
        int unresolvedGearCount)
    {
        if (selectedAct >= 3)
        {
            return "Act 3 is the final act.";
        }

        if (!nextActGuideExists)
        {
            return "The next act database is not installed.";
        }

        if (!activeGuideLoaded)
        {
            return
                $"Act {selectedAct} guide data must finish loading before this gate can unlock.";
        }

        if (!activeRouteAvailable)
        {
            return
                $"Act {selectedAct} route coverage must be reviewed before this gate can unlock.";
        }

        return unresolvedGearCount > 0
            ? $"Review {unresolvedGearCount} equipment item" +
              $"{(unresolvedGearCount == 1 ? string.Empty : "s")} first."
            : null;
    }

    public static string? FinalActBlockedReason(
        HonorRun run,
        bool activeGuideLoaded,
        bool activeRouteAvailable,
        int activeWalkthroughStepCount,
        int unresolvedGearCount)
    {
        if ((run.SelectedAct ?? 1) != 3)
        {
            return "Only Act 3 can complete the run.";
        }

        if (run.FinalActRecord is not null)
        {
            return "The final Act 3 ledger is already locked.";
        }

        if (!activeGuideLoaded || !activeRouteAvailable)
        {
            return "Act 3 guide data must finish loading first.";
        }

        if (activeWalkthroughStepCount > 0)
        {
            return
                $"Resolve or deliberately skip {activeWalkthroughStepCount} route step" +
                $"{(activeWalkthroughStepCount == 1 ? string.Empty : "s")} first.";
        }

        return unresolvedGearCount > 0
            ? $"Review {unresolvedGearCount} equipment item" +
              $"{(unresolvedGearCount == 1 ? string.Empty : "s")} first."
            : null;
    }

    public static bool TryAdvance(
        HonorRun run,
        ActGuideSummary? nextActGuide,
        bool activeGuideLoaded,
        bool activeRouteAvailable,
        IReadOnlyList<BuildGear> currentActGear,
        IReadOnlyList<string> routeConsequences,
        bool acceptingRouteConsequences,
        DateTimeOffset advancedAt)
    {
        var selectedAct = run.SelectedAct ?? 1;
        var unresolved = UnresolvedGear(run, selectedAct, currentActGear);
        if (TransitionBlockedReason(
                selectedAct,
                nextActGuide is not null,
                activeGuideLoaded,
                activeRouteAvailable,
                unresolved.Count) is not null ||
            (routeConsequences.Count > 0 && !acceptingRouteConsequences))
        {
            return false;
        }

        var review = CompleteReview(run, selectedAct, currentActGear);
        if (review is null)
        {
            return false;
        }

        var toAct = selectedAct + 1;
        run.ActTransitions ??= [];
        run.ActTransitions.RemoveAll(transition => transition.FromAct == selectedAct);
        run.ActTransitions.Add(
            new ActTransitionRecord(
                selectedAct,
                toAct,
                review,
                routeConsequences.Count,
                advancedAt,
                currentActGear.ToList()));
        run.SelectedAct = toAct;
        run.SelectedCheckpointId = null;
        run.FocusedWalkthroughStepId = null;
        run.MapRegion = nextActGuide?.Title ?? $"Act {toAct}";
        return true;
    }

    public static bool TryFinalizeActThree(
        HonorRun run,
        bool activeGuideLoaded,
        bool activeRouteAvailable,
        int activeWalkthroughStepCount,
        IReadOnlyList<BuildGear> currentActGear,
        IReadOnlyList<string> routeConsequences,
        bool acceptingRouteConsequences,
        DateTimeOffset advancedAt)
    {
        var unresolved = UnresolvedGear(run, 3, currentActGear);
        if (FinalActBlockedReason(
                run,
                activeGuideLoaded,
                activeRouteAvailable,
                activeWalkthroughStepCount,
                unresolved.Count) is not null ||
            (routeConsequences.Count > 0 && !acceptingRouteConsequences))
        {
            return false;
        }

        var review = CompleteReview(run, 3, currentActGear);
        if (review is null)
        {
            return false;
        }

        run.FinalActRecord = new ActTransitionRecord(
            3,
            3,
            review,
            routeConsequences.Count,
            advancedAt,
            currentActGear.ToList());
        return true;
    }

    private static Dictionary<string, ActGearReviewStatus>? CompleteReview(
        HonorRun run,
        int act,
        IReadOnlyList<BuildGear> gear)
    {
        var review = new Dictionary<string, ActGearReviewStatus>(StringComparer.Ordinal);
        foreach (var item in gear)
        {
            var status = ReviewStatus(run, item, act);
            if (status is null)
            {
                return null;
            }

            review[item.ItemKey] = status.Value;
        }

        return review;
    }
}
