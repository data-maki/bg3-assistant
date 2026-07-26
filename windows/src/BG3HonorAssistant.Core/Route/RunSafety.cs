using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Route;

public sealed record RouteDependencyPresentation(string? Note, bool RequiresAttention);

public static class RunSafety
{
    private static readonly IReadOnlyList<string> CapabilityTerms =
    [
        "silence",
        "calm emotions",
        "sanctuary",
        "command",
        "bludgeoning",
        "fire",
        "counterspell",
        "initiative",
        "control",
    ];

    public static CheckpointDisposition WalkthroughDisposition(
        WalkthroughStep step,
        IReadOnlyDictionary<string, CheckpointDisposition> walkthroughProgress)
    {
        return walkthroughProgress.GetValueOrDefault(step.Id, CheckpointDisposition.Pending);
    }

    public static WalkthroughStep? NextWalkthroughStep(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition> walkthroughProgress,
        IReadOnlyDictionary<string, string>? walkthroughOutcomes,
        int partyLevel)
    {
        var pending = walkthrough
            .Where(step =>
                WalkthroughDisposition(step, walkthroughProgress) == CheckpointDisposition.Pending)
            .ToList();
        if (pending.Count == 0)
        {
            return null;
        }

        var phase = pending.Min(step => step.PhaseOrder);
        var eligible = pending
            .Where(step => step.PhaseOrder == phase)
            .OrderBy(step => step.Order)
            .Where(step => DependencyBlockers(
                step,
                walkthrough,
                walkthroughProgress,
                walkthroughOutcomes).Count == 0)
            .ToList();
        return eligible.FirstOrDefault(step => step.MinimumLevel <= partyLevel)
            ?? eligible.FirstOrDefault();
    }

    public static IReadOnlyList<string> DependencyBlockers(
        WalkthroughStep step,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition> walkthroughProgress,
        IReadOnlyDictionary<string, string>? walkthroughOutcomes = null)
    {
        var outcomes = walkthroughOutcomes ?? new Dictionary<string, string>();
        var titles = walkthrough.ToDictionary(candidate => candidate.Id, candidate => candidate.Title);
        var blockers = new List<string>();

        foreach (var dependency in step.Dependencies)
        {
            var status = walkthroughProgress.GetValueOrDefault(
                dependency.StepId,
                CheckpointDisposition.Pending);
            var satisfied = dependency.Kind switch
            {
                "warning_only" => true,
                "completion_required" => status.CountsAsCompleted(),
                "outcome_required" =>
                    status == CheckpointDisposition.CaughtUp ||
                    (status == CheckpointDisposition.Completed &&
                     outcomes.GetValueOrDefault(dependency.StepId) == dependency.RequiredOutcome),
                _ => status != CheckpointDisposition.Pending,
            };

            if (satisfied)
            {
                continue;
            }

            if (status == CheckpointDisposition.Skipped &&
                dependency.Kind is "completion_required" or "outcome_required")
            {
                blockers.Add(
                    $"Revisit {titles.GetValueOrDefault(dependency.StepId, dependency.StepId)} — " +
                    dependency.Reason);
            }
            else
            {
                blockers.Add(dependency.Reason);
            }
        }

        return blockers;
    }

    public static RouteDependencyPresentation DependencyPresentation(
        WalkthroughStep step,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition> walkthroughProgress,
        IReadOnlyDictionary<string, string>? walkthroughOutcomes,
        WalkthroughStep? recommendedStep,
        IReadOnlyList<WalkthroughStep> activeSteps)
    {
        var blockers = DependencyBlockers(
            step,
            walkthrough,
            walkthroughProgress,
            walkthroughOutcomes);
        if (blockers.Count == 0)
        {
            var currentPhaseOrder = recommendedStep?.PhaseOrder ??
                                    (activeSteps.Count == 0
                                        ? (int?)null
                                        : activeSteps.Min(candidate => candidate.PhaseOrder));
            return currentPhaseOrder is not null &&
                   step.PhaseOrder > currentPhaseOrder
                ? new RouteDependencyPresentation(step.Phase, false)
                : new RouteDependencyPresentation(null, false);
        }

        foreach (var dependency in step.Dependencies.Where(
                     dependency => dependency.Kind != "warning_only"))
        {
            var prerequisite = walkthrough.FirstOrDefault(
                candidate => candidate.Id == dependency.StepId);
            if (prerequisite is null)
            {
                continue;
            }

            var disposition = WalkthroughDisposition(
                prerequisite,
                walkthroughProgress);
            var satisfied = dependency.Kind switch
            {
                "completion_required" => disposition.CountsAsCompleted(),
                "outcome_required" =>
                    disposition == CheckpointDisposition.CaughtUp ||
                    (disposition == CheckpointDisposition.Completed &&
                     walkthroughOutcomes?.GetValueOrDefault(prerequisite.Id) ==
                     dependency.RequiredOutcome),
                _ => disposition != CheckpointDisposition.Pending,
            };
            if (satisfied)
            {
                continue;
            }

            return disposition switch
            {
                CheckpointDisposition.Pending => new(
                    $"After {prerequisite.Title}",
                    false),
                CheckpointDisposition.Skipped => new(
                    $"Revisit {prerequisite.Title}",
                    true),
                _ => new(
                    $"Route changed after {prerequisite.Title}",
                    true),
            };
        }

        return new RouteDependencyPresentation(blockers[0], true);
    }

    public static ReadinessResponse AssessReadiness(
        RouteCheckpoint checkpoint,
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyList<PartyMember> activeParty,
        IReadOnlySet<string> completedIds,
        IReadOnlySet<string> checkedPreparation,
        IReadOnlyDictionary<string, CheckpointDisposition> walkthroughProgress,
        IReadOnlyDictionary<string, string> walkthroughOutcomes,
        IReadOnlyList<BuildSummary> builds)
    {
        var partyLevel = activeParty.Count == 0 ? 1 : activeParty.Min(member => member.Level);
        var blockers = new List<string>();
        var warnings = new List<string>();
        var buildActions = new List<string>();

        if (activeParty.Count == 0)
        {
            blockers.Add(
                "No active party is recorded; confirm the active group before using readiness.");
        }
        else if (partyLevel < checkpoint.MinimumLevel)
        {
            blockers.Add(
                $"Lowest party member is level {partyLevel}; guide minimum is level " +
                $"{checkpoint.MinimumLevel}.");
        }

        var missingPrerequisites = checkpoint.Prerequisites
            .Where(id => !completedIds.Contains(id))
            .Select(id => route.FirstOrDefault(candidate => candidate.Id == id)?.Name ?? id)
            .ToList();
        if (missingPrerequisites.Count > 0)
        {
            blockers.Add(
                "Unresolved reviewed route sequence: " + string.Join(", ", missingPrerequisites));
        }

        var owningStep = walkthrough.FirstOrDefault(step => step.CheckpointId == checkpoint.Id);
        if (owningStep is not null)
        {
            blockers.AddRange(DependencyBlockers(
                owningStep,
                walkthrough,
                walkthroughProgress,
                walkthroughOutcomes));
        }

        warnings.AddRange(checkpoint.IrreversibleWarnings);
        var uncheckedPreparation = checkpoint.Preparation
            .Where(item => !checkedPreparation.Contains(item))
            .ToList();
        if (uncheckedPreparation.Count > 0)
        {
            warnings.Add(
                "Preparation not confirmed: " + string.Join("; ", uncheckedPreparation));
        }

        var buildsById = builds
            .GroupBy(build => build.Id)
            .ToDictionary(group => group.Key, group => group.First());
        var assumedBuildSetup = new List<string>();
        foreach (var member in activeParty)
        {
            if (member.BuildId is null)
            {
                continue;
            }

            if (!buildsById.TryGetValue(member.BuildId, out var build))
            {
                warnings.Add(
                    $"{member.Name} has an unknown build assignment ({member.BuildId}).");
                continue;
            }

            var reviewedLevels = build.Levels.Where(level => level.Level <= member.Level).ToList();
            assumedBuildSetup.AddRange([build.Role, build.PlayPattern, build.ClassProgression]);
            assumedBuildSetup.AddRange(reviewedLevels.Select(level =>
                $"{level.Take} {level.SubclassChoice} {level.Choices} {level.Tactics}"));
            var levelPlan = build.Levels.FirstOrDefault(level => level.Level == member.Level);
            if (levelPlan is not null)
            {
                buildActions.Add(
                    $"{member.Name} L{member.Level} ({build.Name}): " +
                    $"{levelPlan.Take}; {levelPlan.Tactics}");
            }
            else if (build.Levels.LastOrDefault() is { } lastLevel)
            {
                warnings.Add(
                    $"{member.Name}'s reviewed {build.Name} plan ends at level {lastLevel.Level}.");
            }
        }

        var requestedText = string.Join(
            " ",
            new[] { checkpoint.Advice }.Concat(checkpoint.Preparation)).ToLowerInvariant();
        var recordedCapabilities = string.Join(
            " ",
            activeParty.SelectMany(member => member.PreparedTags).Concat(assumedBuildSetup))
            .ToLowerInvariant();
        foreach (var capability in CapabilityTerms)
        {
            if (requestedText.Contains(capability, StringComparison.Ordinal) &&
                !recordedCapabilities.Contains(capability, StringComparison.Ordinal))
            {
                warnings.Add(
                    $"Party capability not recorded: {capability}. " +
                    "Confirm the party has it or choose an alternative plan.");
            }
        }

        var status = blockers.Count > 0
            ? "blocked"
            : checkpoint.Danger == "extreme" || checkpoint.IrreversibleWarnings.Count > 0
                ? "danger"
                : checkpoint.Danger == "high" || warnings.Count > 0
                    ? "caution"
                    : "ready";
        var nextActions = blockers.Take(2)
            .Concat(uncheckedPreparation.Take(2))
            .Concat(buildActions.Take(2))
            .ToList();
        if (nextActions.Count == 0)
        {
            nextActions.Add(checkpoint.Advice);
        }

        return new ReadinessResponse(
            status,
            partyLevel,
            checkpoint.MinimumLevel,
            blockers,
            warnings,
            nextActions);
    }

    public static RouteCheckpoint? NextCheckpoint(
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions,
        string? selectedId,
        int partyLevel)
    {
        if (selectedId is not null &&
            route.FirstOrDefault(checkpoint => checkpoint.Id == selectedId) is { } selected)
        {
            return selected;
        }

        var pending = route
            .Where(checkpoint =>
                dispositions.GetValueOrDefault(
                    checkpoint.Id,
                    CheckpointDisposition.Pending) == CheckpointDisposition.Pending)
            .ToList();
        if (pending.Count == 0)
        {
            return null;
        }

        var phase = pending.Min(RoutePhase);
        var phasePending = pending.Where(checkpoint => RoutePhase(checkpoint) == phase).ToList();
        var resolved = dispositions
            .Where(pair => pair.Value != CheckpointDisposition.Pending)
            .Select(pair => pair.Key)
            .ToHashSet(StringComparer.Ordinal);
        var eligible = phasePending
            .Where(checkpoint => checkpoint.Prerequisites.All(resolved.Contains))
            .ToList();
        var candidates = eligible.Count == 0 ? phasePending : eligible;
        var atOrBelowLevel = candidates
            .Where(checkpoint => checkpoint.MinimumLevel <= partyLevel)
            .ToList();
        return (atOrBelowLevel.Count == 0 ? candidates : atOrBelowLevel)
            .OrderBy(checkpoint => Math.Abs(checkpoint.MinimumLevel - partyLevel))
            .ThenBy(checkpoint => checkpoint.RouteOrder)
            .FirstOrDefault();
    }

    public static LevelActivityPlan? ActivityPlan(
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions,
        string? selectedId,
        int partyLevel)
    {
        var recommendation = NextCheckpoint(
            route,
            dispositions,
            selectedId,
            partyLevel);
        if (recommendation is null)
        {
            return null;
        }

        var pending = route
            .Where(
                checkpoint =>
                    dispositions.GetValueOrDefault(
                        checkpoint.Id,
                        CheckpointDisposition.Pending) ==
                    CheckpointDisposition.Pending)
            .ToList();
        var phase = RoutePhase(recommendation);
        var phasePending = pending
            .Where(checkpoint => RoutePhase(checkpoint) == phase)
            .ToList();
        var resolved = dispositions
            .Where(pair => pair.Value != CheckpointDisposition.Pending)
            .Select(pair => pair.Key)
            .ToHashSet(StringComparer.Ordinal);
        var eligible = phasePending
            .Where(
                checkpoint =>
                    checkpoint.Prerequisites.All(resolved.Contains))
            .ToList();
        var safeXp = eligible
            .Where(
                checkpoint =>
                    checkpoint.Importance == "minor" &&
                    checkpoint.MinimumLevel <= partyLevel)
            .OrderBy(checkpoint => checkpoint.RouteOrder)
            .ToList();
        var major = phasePending
            .Where(checkpoint => checkpoint.Importance == "major")
            .OrderBy(
                checkpoint => Math.Abs(checkpoint.MinimumLevel - partyLevel))
            .ThenBy(checkpoint => checkpoint.RouteOrder)
            .FirstOrDefault();

        string activityLabel;
        string gateAdvice;
        if (recommendation.MinimumLevel > partyLevel)
        {
            activityLabel = "EARN XP FIRST";
            gateAdvice =
                $"This needs L{recommendation.MinimumLevel}. Do quests and " +
                $"the safe fights in {RoutePhaseName(recommendation)}, then come back.";
        }
        else if (recommendation.Importance == "major")
        {
            activityLabel = "MAIN FIGHT";
            gateAdvice =
                "You're at level. Review the fight plan, then start it on your terms.";
        }
        else
        {
            activityLabel = "SAFE XP";
            gateAdvice = major is not null && major.MinimumLevel > partyLevel
                ? $"Safe at your level — builds XP toward {major.Name} " +
                  $"(L{major.MinimumLevel})."
                : "Safe at your level. Clear it before the main fight.";
        }

        return new LevelActivityPlan(
            activityLabel,
            RoutePhaseName(recommendation),
            recommendation,
            safeXp,
            major,
            gateAdvice);
    }

    public static IReadOnlyList<string> ActTwoBlockers(
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions)
    {
        return RouteConsequences(route, dispositions);
    }

    public static IReadOnlyList<string> RouteConsequences(
        IReadOnlyList<RouteCheckpoint> route,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions)
    {
        var consequences = new List<string>();
        foreach (var checkpoint in route)
        {
            var state = dispositions.GetValueOrDefault(
                checkpoint.Id,
                CheckpointDisposition.Pending);
            if (state.CountsAsCompleted() ||
                (checkpoint.Importance != "major" &&
                 checkpoint.IrreversibleWarnings.Count == 0))
            {
                continue;
            }

            var prefix = state == CheckpointDisposition.Skipped ? "Skipped" : "Unresolved";
            var reason = checkpoint.IrreversibleWarnings.FirstOrDefault()
                ?? "major checkpoint unresolved";
            consequences.Add($"{prefix} — {checkpoint.Name}: {reason}");
        }

        return consequences;
    }

    public static int RoutePhase(RouteCheckpoint checkpoint)
    {
        return checkpoint.Region switch
        {
            "Nautiloid" => 0,
            "Underdark" => 2,
            "Grymforge" => 3,
            "Crèche Y'llek" => 4,
            _ => 1,
        };
    }

    public static string RoutePhaseName(RouteCheckpoint checkpoint)
    {
        if (checkpoint.Id.StartsWith("act3-", StringComparison.Ordinal))
        {
            return checkpoint.Region;
        }

        return RoutePhase(checkpoint) switch
        {
            0 => "Nautiloid",
            1 => "Wilderness cleanup",
            2 => "Underdark",
            3 => "Grymforge",
            _ => "Mountain Pass / Crèche",
        };
    }
}
