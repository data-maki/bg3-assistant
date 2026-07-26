using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Route;

public sealed record GearTargetContext(PartyMember Member, BuildGear Gear)
{
    public bool Matches(string gearId, string memberId) =>
        Gear.Id == gearId && Member.Id == memberId;
}

public abstract record CurrentGoal
{
    private CurrentGoal()
    {
    }

    public bool HasCurrentTask =>
        this is GearTargetGoal or WalkthroughStepGoal or CheckpointGoal;

    public bool HasGuidedGoal =>
        this is WalkthroughStepGoal or CheckpointGoal;

    public sealed record GearTargetGoal(GearTargetContext Context) : CurrentGoal;

    public sealed record WalkthroughStepGoal(WalkthroughStep Step) : CurrentGoal;

    public sealed record CheckpointGoal(RouteCheckpoint Checkpoint) : CurrentGoal;

    public sealed record LaterActGoal : CurrentGoal;

    public sealed record RouteCompleteGoal : CurrentGoal;
}

public sealed record CurrentGoalPresentation(
    string Title,
    string Area,
    int MinimumLevel,
    string Avoid,
    string Danger);

public static class CurrentGoalRules
{
    public const string ActTwoUnavailableMessage =
        "Act 2 route is not available in this guide version";

    public static CurrentGoal Select(
        GearTargetContext? target,
        bool activeRouteAvailable,
        WalkthroughStep? currentStep,
        RouteCheckpoint? currentCheckpoint)
    {
        if (target is not null)
        {
            return new CurrentGoal.GearTargetGoal(target);
        }

        if (!activeRouteAvailable)
        {
            return new CurrentGoal.LaterActGoal();
        }

        if (currentStep is not null)
        {
            return new CurrentGoal.WalkthroughStepGoal(currentStep);
        }

        return currentCheckpoint is not null
            ? new CurrentGoal.CheckpointGoal(currentCheckpoint)
            : new CurrentGoal.RouteCompleteGoal();
    }

    public static CurrentGoalPresentation Present(
        CurrentGoal goal,
        int selectedAct,
        int lowestPartyLevel,
        bool routeHasConsequentialSkips,
        bool activeGuideLoaded,
        string statusMessage,
        string? currentActTitle,
        IReadOnlyList<RouteCheckpoint> route,
        RouteCheckpoint? currentCheckpoint)
    {
        return goal switch
        {
            CurrentGoal.GearTargetGoal target => new(
                $"Get {target.Context.Gear.Item}",
                target.Context.Gear.Region,
                target.Context.Gear.MinimumLevel ?? lowestPartyLevel,
                "Confirm the acquisition before marking this target complete.",
                "low"),
            CurrentGoal.WalkthroughStepGoal step => new(
                step.Step.Title,
                step.Step.Area,
                step.Step.MinimumLevel,
                step.Step.Incident?.Never ?? step.Step.Avoid,
                StepDanger(step.Step, route, currentCheckpoint)),
            CurrentGoal.CheckpointGoal checkpoint => new(
                checkpoint.Checkpoint.Name,
                checkpoint.Checkpoint.Area,
                checkpoint.Checkpoint.MinimumLevel,
                checkpoint.Checkpoint.FailureConditions.FirstOrDefault() ??
                checkpoint.Checkpoint.Advice,
                checkpoint.Checkpoint.Danger),
            CurrentGoal.LaterActGoal => new(
                currentActTitle ?? $"Act {selectedAct}",
                string.Empty,
                lowestPartyLevel,
                selectedAct == 2
                    ? ActTwoUnavailableMessage
                    : activeGuideLoaded
                        ? "Step-by-step route guidance is not available for this act yet."
                        : statusMessage,
                "low"),
            CurrentGoal.RouteCompleteGoal => new(
                routeHasConsequentialSkips
                    ? $"Act {selectedAct} resolved with skips"
                    : $"Act {selectedAct} complete",
                string.Empty,
                lowestPartyLevel,
                routeHasConsequentialSkips
                    ? "Revisit required or recommended skipped steps before treating this route as complete."
                    : selectedAct < 3
                        ? $"Review the Act {selectedAct + 1} gate before advancing."
                        : "The final route is resolved.",
                "low"),
            _ => throw new ArgumentOutOfRangeException(nameof(goal)),
        };
    }

    private static string StepDanger(
        WalkthroughStep step,
        IReadOnlyList<RouteCheckpoint> route,
        RouteCheckpoint? currentCheckpoint)
    {
        if (step.CheckpointId is not null &&
            route.FirstOrDefault(checkpoint => checkpoint.Id == step.CheckpointId) is { } linked)
        {
            return linked.Danger;
        }

        if (step.Incident is not null)
        {
            return "high";
        }

        return step.Kind == "dialogue"
            ? "medium"
            : currentCheckpoint?.Danger ?? "low";
    }
}
