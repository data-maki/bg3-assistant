using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Route;

public sealed record DispositionRequest(
    CheckpointDisposition Disposition,
    bool RequiresConfirmation,
    string? ConfirmationMessage);

public static class RunProgressRules
{
    public static IReadOnlyList<WalkthroughStep> ActiveSteps(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress) =>
        walkthrough
            .Where(
                step =>
                    RunSafety.WalkthroughDisposition(step, progress ?? EmptyProgress) ==
                    CheckpointDisposition.Pending)
            .ToList();

    public static IReadOnlyList<WalkthroughStep> VisibleSteps(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress,
        RouteRevealPolicy revealPolicy)
    {
        var pending = ActiveSteps(walkthrough, progress)
            .OrderBy(step => step.Order);
        return (revealPolicy == RouteRevealPolicy.NextThree
                ? pending.Take(3)
                : pending)
            .ToList();
    }

    public static IReadOnlyList<WalkthroughStep> ArchivedSteps(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress) =>
        walkthrough
            .Where(
                step =>
                    RunSafety.WalkthroughDisposition(step, progress ?? EmptyProgress) !=
                    CheckpointDisposition.Pending)
            .ToList();

    public static WalkthroughStep? SaferAlternative(
        WalkthroughStep? current,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress,
        int lowestPartyLevel)
    {
        if (current is null)
        {
            return null;
        }

        var unresolved = ActiveSteps(walkthrough, progress)
            .Where(
                step =>
                    step.Id != current.Id &&
                    step.MinimumLevel <= lowestPartyLevel)
            .ToList();
        var local = unresolved.Where(step => step.Region == current.Region).ToList();
        var samePhase = unresolved
            .Where(step => step.PhaseOrder == current.PhaseOrder)
            .ToList();
        return (local.Count == 0 ? samePhase : local)
            .OrderBy(step => step.MinimumLevel)
            .ThenBy(step => step.Order)
            .FirstOrDefault();
    }

    public static bool RouteHasConsequentialSkips(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress) =>
        walkthrough.Any(
            step =>
                RunSafety.WalkthroughDisposition(step, progress ?? EmptyProgress) ==
                CheckpointDisposition.Skipped &&
                step.Importance != "optional");

    public static bool SetWalkthroughDisposition(
        HonorRun run,
        WalkthroughStep step,
        CheckpointDisposition disposition)
    {
        if (run.ActLedgerIsLocked(run.SelectedAct ?? 1))
        {
            return false;
        }

        run.WalkthroughProgress ??= [];
        if (disposition == CheckpointDisposition.Pending)
        {
            run.WalkthroughProgress.Remove(step.Id);
            run.WalkthroughOutcomes?.Remove(step.Id);
        }
        else
        {
            run.WalkthroughProgress[step.Id] = disposition;
        }

        if (disposition != CheckpointDisposition.Pending &&
            run.SelectedCheckpointId == step.CheckpointId)
        {
            run.SelectedCheckpointId = null;
        }

        if (disposition == CheckpointDisposition.Pending)
        {
            run.FocusRoute(step.Id, step.CheckpointId);
        }
        else if (run.FocusedWalkthroughStepId == step.Id)
        {
            run.FocusedWalkthroughStepId = null;
        }

        return true;
    }

    public static bool ResolveOutcome(
        HonorRun run,
        WalkthroughStep step,
        string outcome)
    {
        if (run.ActLedgerIsLocked(run.SelectedAct ?? 1))
        {
            return false;
        }

        run.WalkthroughOutcomes ??= [];
        run.WalkthroughOutcomes[step.Id] = outcome;
        return SetWalkthroughDisposition(
            run,
            step,
            CheckpointDisposition.Completed);
    }

    public static bool SetCheckpointDisposition(
        HonorRun run,
        RouteCheckpoint checkpoint,
        IReadOnlyList<WalkthroughStep> walkthrough,
        CheckpointDisposition disposition,
        string note,
        DateTimeOffset updatedAt)
    {
        var step = walkthrough.FirstOrDefault(
            candidate => candidate.CheckpointId == checkpoint.Id);
        if (step is null)
        {
            return false;
        }

        run.Progress.TryGetValue(checkpoint.Id, out var current);
        run.Progress[checkpoint.Id] = (current ?? new CheckpointProgress()) with
        {
            SkipNote = note,
            UpdatedAt = updatedAt,
        };
        return SetWalkthroughDisposition(run, step, disposition);
    }

    public static DispositionRequest RequestDisposition(
        RouteCheckpoint checkpoint,
        CheckpointDisposition disposition)
    {
        var requiresConfirmation =
            disposition == CheckpointDisposition.Skipped &&
            checkpoint.IrreversibleWarnings.Count > 0;
        return new DispositionRequest(
            disposition,
            requiresConfirmation,
            requiresConfirmation
                ? $"Confirm {disposition.ToString().ToLowerInvariant()}: " +
                  "this checkpoint has irreversible or time-sensitive consequences."
                : null);
    }

    public static bool ToggleMute(HonorRun run, string checkpointId)
    {
        run.MutedCheckpointIds ??= [];
        return run.MutedCheckpointIds.Remove(checkpointId)
            ? false
            : run.MutedCheckpointIds.Add(checkpointId);
    }

    public static IncidentProtocol? IncidentProtocol(
        WalkthroughStep step,
        IReadOnlyList<RouteCheckpoint> route)
    {
        if (step.Incident is not null)
        {
            return step.Incident;
        }

        var checkpoint = step.CheckpointId is null
            ? null
            : route.FirstOrDefault(candidate => candidate.Id == step.CheckpointId);
        if (checkpoint is null)
        {
            return null;
        }

        return new IncidentProtocol
        {
            Trigger = checkpoint.FailureConditions.FirstOrDefault() ??
                      "The encounter stops following the prepared plan.",
            SafeActions = checkpoint.Preparation.Take(3).ToList(),
            Never = string.IsNullOrEmpty(step.Avoid) ? checkpoint.Advice : step.Avoid,
            Escape =
                "Preserve one character with mobility or invisibility and use the " +
                "prepared exit if the encounter allows fleeing.",
            HonorDelta = checkpoint.LegendaryAction ??
                         "No additional Honor-only mechanic is recorded for this encounter.",
            PostFight = [],
            Authority = "guide_fact",
            SourceUrl = checkpoint.Source.Url ?? string.Empty,
        };
    }

    private static readonly IReadOnlyDictionary<string, CheckpointDisposition> EmptyProgress =
        new Dictionary<string, CheckpointDisposition>();
}
