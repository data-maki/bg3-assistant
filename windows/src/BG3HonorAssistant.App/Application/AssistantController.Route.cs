using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    public async Task FocusStepAsync(
        WalkthroughStep step,
        CancellationToken cancellationToken = default)
    {
        if (RunSafety.WalkthroughDisposition(
                step,
                Run.WalkthroughProgress ?? EmptyProgress) !=
            CheckpointDisposition.Pending)
        {
            return;
        }

        Run.FocusRoute(step.Id, step.CheckpointId);
        Run.MapRegion = step.Region;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task FollowRecommendationAsync(
        CancellationToken cancellationToken = default)
    {
        Run.FocusRoute(null, null);
        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
    }

    public DispositionRequest RequestDisposition(CheckpointDisposition disposition) =>
        CurrentCheckpoint is null
            ? new(disposition, false, null)
            : RunProgressRules.RequestDisposition(CurrentCheckpoint, disposition);

    public async Task<bool> SetCurrentDispositionAsync(
        CheckpointDisposition disposition,
        string note = "",
        CancellationToken cancellationToken = default)
    {
        var step = CurrentStep;
        if (step is null)
        {
            return false;
        }

        var applied = step.CheckpointId is { } checkpointId &&
                      Route.FirstOrDefault(checkpoint => checkpoint.Id == checkpointId) is
                          { } checkpoint
            ? RunProgressRules.SetCheckpointDisposition(
                Run,
                checkpoint,
                Walkthrough,
                disposition,
                note,
                DateTimeOffset.UtcNow)
            : RunProgressRules.SetWalkthroughDisposition(Run, step, disposition);
        if (!applied)
        {
            return false;
        }

        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> CompleteCurrentGoalAsync(
        CancellationToken cancellationToken = default)
    {
        if (TargetContext is not { } target)
        {
            if (CurrentStep?.Decision is not null)
            {
                return false;
            }

            return await SetCurrentDispositionAsync(
                CheckpointDisposition.Completed,
                cancellationToken: cancellationToken);
        }

        if (!target.Gear.IsMapObjective)
        {
            return false;
        }

        if (Run.EquipmentOwnerId(target.Gear.ItemKey) == target.Member.Id)
        {
            Run.GearTarget = null;
        }
        else if (Run.ToggleEquipment(target.Gear.ItemKey, target.Member.Id))
        {
            Run.GearTarget = null;
        }
        else
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> ResolveOutcomeAsync(
        WalkthroughStep step,
        string outcome,
        CancellationToken cancellationToken = default)
    {
        if (!RunProgressRules.ResolveOutcome(Run, step, outcome))
        {
            return false;
        }

        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task ToggleMuteCurrentAsync(
        CancellationToken cancellationToken = default)
    {
        if (CurrentCheckpoint is not { } checkpoint)
        {
            return;
        }

        RunProgressRules.ToggleMute(Run, checkpoint.Id);
        await SaveAsync(cancellationToken);
        Notify();
    }

    public bool PinCurrentFight()
    {
        if (CurrentCheckpoint is null || Readiness?.Status == "blocked")
        {
            return false;
        }

        CombatCardPinned = true;
        Notify();
        return true;
    }

    public void UnpinFight()
    {
        CombatCardPinned = false;
        Notify();
    }

    public void SnoozeWarnings()
    {
        SnoozedUntil = DateTimeOffset.UtcNow.AddMinutes(10);
        Notify();
    }
}
