using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    private const string PreferencesKey = "assistant.preferences";
    private readonly RunRepository runRepository;
    private readonly GuideRepository guideRepository;
    private readonly JsonSerializerOptions json = JsonDefaults.Create();
    private readonly List<ImportedBuild> importedBuilds = [];

    public AssistantController(RunRepository runRepository, GuideRepository guideRepository)
    {
        this.runRepository = runRepository;
        this.guideRepository = guideRepository;
    }

    public event EventHandler? StateChanged;

    public GuideBundle Guide { get; private set; } = null!;

    public HonorRun Run { get; private set; } = null!;

    public AppPreferences Preferences { get; private set; } = new();

    public IReadOnlyList<SavedRun> Runs { get; private set; } = [];

    public string? RecoveryNotice { get; private set; }

    public bool CombatCardPinned { get; private set; }

    public DateTimeOffset? SnoozedUntil { get; private set; }

    public RoutePayload Payload =>
        Guide.Payloads[(Run.SelectedAct ?? 1).ToString()];

    public IReadOnlyList<WalkthroughStep> Walkthrough => Payload.Walkthrough;

    public IReadOnlyList<RouteCheckpoint> Route => Payload.Checkpoints;

    public IReadOnlyList<BuildSummary> Builds =>
        Payload.Builds
            .Concat(importedBuilds.Select(imported => imported.Build))
            .GroupBy(build => build.Id, StringComparer.Ordinal)
            .Select(group => group.Last())
            .ToList();

    public IReadOnlyList<ImportedBuild> ImportedBuilds => importedBuilds;

    public GearTargetContext? TargetContext
    {
        get
        {
            if (Run.GearTarget is not { } target)
            {
                return null;
            }

            var member = ActiveParty.FirstOrDefault(
                candidate =>
                    candidate.Id == target.MemberId &&
                    candidate.BuildId == target.BuildId);
            if (member is null)
            {
                return null;
            }

            var gear = PartyPlanningRules.WantedGear(
                    Run,
                    member,
                    Run.SelectedAct ?? 1,
                    Builds,
                    Guide.Items)
                .FirstOrDefault(
                    candidate =>
                        candidate.Id == target.GearId &&
                        candidate.Act == (Run.SelectedAct ?? 1));
            return gear is null ? null : new GearTargetContext(member, gear);
        }
    }

    public IReadOnlyList<PartyMember> ActiveParty => Run.Party;

    public IReadOnlyList<GearPickup> RoutePickups =>
        PartyPlanningRules.RoutePickups(Run, Builds, Guide.Items);

    public IReadOnlyList<BuildGear> CurrentActGear =>
        ActGear(Run.SelectedAct ?? 1);

    public IReadOnlyList<BuildGear> ActGear(int act)
    {
        var unique = new Dictionary<string, BuildGear>(StringComparer.Ordinal);
        foreach (var member in ActiveParty)
        {
            foreach (var gear in PartyPlanningRules.WantedGear(
                         Run,
                         member,
                         act,
                         Builds,
                         Guide.Items)
                     .Where(gear => gear.Act == act && gear.IsMapObjective))
            {
                unique.TryAdd(gear.ItemKey, gear);
            }
        }

        return ActTransitionRules.ActGear(
            Run,
            act,
            unique.Values.ToList(),
            Guide.Items);
    }

    public int LowestPartyLevel =>
        ActiveParty.Count == 0 ? 1 : ActiveParty.Min(member => member.Level);

    public WalkthroughStep? CurrentStep
    {
        get
        {
            var focused = Run.FocusedWalkthroughStepId is null
                ? null
                : Walkthrough.FirstOrDefault(
                    step =>
                        step.Id == Run.FocusedWalkthroughStepId &&
                        RunSafety.WalkthroughDisposition(
                            step,
                            Run.WalkthroughProgress ?? EmptyProgress) ==
                        CheckpointDisposition.Pending);
            return focused ??
                   RunSafety.NextWalkthroughStep(
                       Walkthrough,
                       Run.WalkthroughProgress ?? EmptyProgress,
                       Run.WalkthroughOutcomes,
                       LowestPartyLevel);
        }
    }

    public RouteCheckpoint? CurrentCheckpoint
    {
        get
        {
            if (Run.SelectedCheckpointId is { } selected &&
                Route.FirstOrDefault(checkpoint => checkpoint.Id == selected) is { } checkpoint)
            {
                return checkpoint;
            }

            if (CurrentStep?.CheckpointId is { } stepCheckpoint &&
                Route.FirstOrDefault(checkpoint => checkpoint.Id == stepCheckpoint) is
                    { } owned)
            {
                return owned;
            }

            return RunSafety.NextCheckpoint(
                Route,
                CheckpointDispositions(),
                selectedId: null,
                LowestPartyLevel);
        }
    }

    public CurrentGoal CurrentGoal =>
        CurrentGoalRules.Select(
            TargetContext,
            activeRouteAvailable: Payload.RouteAvailable,
            CurrentStep,
            CurrentCheckpoint);

    public CurrentGoalPresentation GoalPresentation =>
        CurrentGoalRules.Present(
            CurrentGoal,
            Run.SelectedAct ?? 1,
            LowestPartyLevel,
            RunProgressRules.RouteHasConsequentialSkips(
                Walkthrough,
                Run.WalkthroughProgress),
            activeGuideLoaded: true,
            statusMessage: "Guide data is unavailable.",
            Payload.Acts.FirstOrDefault(act => act.Act == (Run.SelectedAct ?? 1))?.Title,
            Route,
            CurrentCheckpoint);

    public ReadinessResponse? Readiness =>
        CurrentCheckpoint is null
            ? null
            : RunSafety.AssessReadiness(
                CurrentCheckpoint,
                Route,
                Walkthrough,
                ActiveParty,
                CompletedCheckpointIds(),
                Run.Progress.GetValueOrDefault(CurrentCheckpoint.Id)?.CheckedPreparation ?? [],
                Run.WalkthroughProgress ?? EmptyProgress,
                Run.WalkthroughOutcomes ?? EmptyOutcomes,
                Builds);

    public bool WarningsSuppressed =>
        SnoozedUntil is { } until && until > DateTimeOffset.UtcNow ||
        CurrentCheckpoint is { } checkpoint &&
        Run.MutedCheckpointIds?.Contains(checkpoint.Id) == true;

    public IReadOnlyList<string> CombatPinLines
    {
        get
        {
            if (CurrentCheckpoint is not { } checkpoint)
            {
                return [];
            }

            var trigger = checkpoint.LegendaryAction ??
                          checkpoint.FailureConditions.FirstOrDefault() ??
                          checkpoint.Advice;
            var protect = checkpoint.FailureConditions.Skip(1).FirstOrDefault() ??
                          GoalPresentation.Avoid;
            return
            [
                $"TRIGGER · {trigger}",
                $"PROTECT · {protect}",
                "EXIT · Keep one mobile survivor able to disengage.",
            ];
        }
    }

    public IReadOnlyList<string> CurrentActConsequences =>
        ActTransitionRules.RouteConsequences(
            Run,
            Run.SelectedAct ?? 1,
            Run.SelectedAct,
            Payload.RouteAvailable,
            Route,
            CheckpointDispositions());

    public string? ActTransitionBlockedReason =>
        ActTransitionRules.TransitionBlockedReason(
            Run.SelectedAct ?? 1,
            Payload.Acts.Any(act => act.Act == (Run.SelectedAct ?? 1) + 1),
            activeGuideLoaded: true,
            Payload.RouteAvailable,
            ActTransitionRules.UnresolvedGear(
                    Run,
                    Run.SelectedAct ?? 1,
                    CurrentActGear)
                .Count);

    public string? FinalActBlockedReason =>
        ActTransitionRules.FinalActBlockedReason(
            Run,
            activeGuideLoaded: true,
            Payload.RouteAvailable,
            RunProgressRules.ActiveSteps(Walkthrough, Run.WalkthroughProgress).Count,
            ActTransitionRules.UnresolvedGear(Run, 3, CurrentActGear).Count);
}
