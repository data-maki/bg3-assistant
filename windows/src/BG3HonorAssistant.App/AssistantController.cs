using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed class AssistantController
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

    public IReadOnlyList<BuildGear> CurrentActGear
    {
        get
        {
            var act = Run.SelectedAct ?? 1;
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

    public async Task InitializeAsync(
        string guidePath,
        CancellationToken cancellationToken = default)
    {
        Guide = await guideRepository.LoadAsync(guidePath, cancellationToken);
        await runRepository.InitializeAsync(cancellationToken);
        Preferences = await LoadPreferencesAsync(cancellationToken);
        await RefreshImportedBuildsAsync(cancellationToken);

        var active = await runRepository.LoadRecoverableActiveAsync(
            SnapshotIsValid,
            cancellationToken);
        if (active is null)
        {
            Run = CreateDefaultRun("Honor Run");
            await SaveAsync(cancellationToken);
        }
        else
        {
            Run = DeserializeRun(active.SnapshotJson);
            Run.NormalizeRoster();
            var runRecoveryNotice = string.Equals(
                active.SnapshotJson,
                (await runRepository.LoadActiveAsync(cancellationToken))?.SnapshotJson,
                StringComparison.Ordinal)
                ? null
                : "Recovered the newest valid run revision after an unreadable snapshot.";
            RecoveryNotice ??= runRecoveryNotice;
        }

        await RefreshRunsAsync(cancellationToken);
        Notify();
    }

    public async Task CreateRunAsync(
        string name,
        RunDifficulty difficulty,
        RouteRevealPolicy revealPolicy,
        CancellationToken cancellationToken = default)
    {
        Run = CreateDefaultRun(string.IsNullOrWhiteSpace(name) ? "Honor Run" : name.Trim());
        Run.Difficulty = difficulty;
        Run.RouteRevealPolicy = revealPolicy;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> SwitchRunAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        var saved = await runRepository.LoadAsync(id, cancellationToken);
        if (saved is null || !SnapshotIsValid(saved.SnapshotJson))
        {
            return false;
        }

        if (!await runRepository.SetActiveAsync(id, cancellationToken))
        {
            return false;
        }

        Run = DeserializeRun(saved.SnapshotJson);
        Run.NormalizeRoster();
        await RefreshRunsAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task RenameRunAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        if (!string.IsNullOrWhiteSpace(name))
        {
            Run.Name = name.Trim();
            await SaveAsync(cancellationToken);
            Notify();
        }
    }

    public async Task SaveAsync(CancellationToken cancellationToken = default)
    {
        var snapshot = JsonSerializer.Serialize(Run, json);
        await runRepository.SaveAsync(
            Run.Id,
            Run.Name ?? "Honor Run",
            Run.GuideVersion,
            snapshot,
            makeActive: true,
            cancellationToken);
        await RefreshRunsAsync(cancellationToken);
    }

    public async Task UpdatePreferencesAsync(
        AppPreferences preferences,
        CancellationToken cancellationToken = default)
    {
        Preferences = preferences;
        await runRepository.SetSettingAsync(
            PreferencesKey,
            JsonSerializer.Serialize(preferences, json),
            cancellationToken);
        Notify();
    }

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

    public async Task SetPartyLevelAsync(
        string memberId,
        int level,
        CancellationToken cancellationToken = default)
    {
        var index = Run.Roster?.FindIndex(member => member.Id == memberId) ?? -1;
        if (index < 0)
        {
            return;
        }

        Run.Roster![index] = PartyPlanningRules.AtLevel(
            Run.Roster[index],
            Math.Clamp(level, 1, 12),
            Builds);
        Run.SyncActivePartyProjection();
        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> AssignBuildAsync(
        string memberId,
        string? buildId,
        CancellationToken cancellationToken = default)
    {
        if (!PartyPlanningRules.AssignBuild(
                Run,
                memberId,
                buildId,
                Builds,
                DateTimeOffset.UtcNow))
        {
            return false;
        }

        _ = PartyPlanningRules.ValidateGearTarget(Run, Builds, Guide.Items);
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> SetGearTargetAsync(
        string memberId,
        BuildGear gear,
        CancellationToken cancellationToken = default)
    {
        var member = ActiveParty.FirstOrDefault(
            candidate => candidate.Id == memberId && candidate.BuildId is not null);
        if (member is null ||
            gear.Act != (Run.SelectedAct ?? 1) ||
            !PartyPlanningRules.WantedGear(
                    Run,
                    member,
                    Run.SelectedAct ?? 1,
                    Builds,
                    Guide.Items)
                .Any(candidate => candidate.Id == gear.Id))
        {
            return false;
        }

        Run.FocusGear(new GearTarget(member.Id, member.BuildId!, gear.Id));
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task ClearGearTargetAsync(
        CancellationToken cancellationToken = default)
    {
        if (Run.GearTarget is null)
        {
            return;
        }

        Run.GearTarget = null;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> MarkGearObtainedAsync(
        string memberId,
        BuildGear gear,
        CancellationToken cancellationToken = default)
    {
        var pickup = RoutePickups.FirstOrDefault(
            candidate =>
                candidate.MemberId == memberId &&
                candidate.Gear.ItemKey == gear.ItemKey);
        if (pickup is null)
        {
            return Run.EquipmentOwnerId(gear.ItemKey) == memberId;
        }

        if (Run.EquipmentOwnerId(gear.ItemKey) != memberId &&
            !Run.ToggleEquipment(gear.ItemKey, memberId))
        {
            return false;
        }

        if (Run.GearTarget is { } target &&
            target.MemberId == memberId &&
            target.GearId == gear.Id)
        {
            Run.GearTarget = null;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> SetActGearReviewAsync(
        BuildGear gear,
        ActGearReviewStatus status,
        CancellationToken cancellationToken = default)
    {
        if (!ActTransitionRules.TrySetReview(
                Run,
                gear,
                Run.SelectedAct ?? 1,
                status))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> AdvanceActAsync(
        bool acceptingRouteConsequences,
        CancellationToken cancellationToken = default)
    {
        var currentAct = Run.SelectedAct ?? 1;
        var destination = Payload.Acts.FirstOrDefault(act => act.Act == currentAct + 1);
        if (!ActTransitionRules.TryAdvance(
                Run,
                destination,
                activeGuideLoaded: true,
                Payload.RouteAvailable,
                CurrentActGear,
                CurrentActConsequences,
                acceptingRouteConsequences,
                DateTimeOffset.UtcNow))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> SetRosterStatusAsync(
        string memberId,
        RosterStatus status,
        CancellationToken cancellationToken = default)
    {
        if (!Run.ApplyRosterStatus(status, memberId))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task SaveImportedBuildAsync(
        ImportedBuild imported,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(imported);
        await runRepository.SaveImportedBuildAsync(
            imported.Id,
            imported.Name,
            JsonSerializer.Serialize(imported, json),
            cancellationToken);
        await RefreshImportedBuildsAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> DeleteImportedBuildAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        if (Run.Party.Any(member => member.BuildId == id))
        {
            return false;
        }

        var deleted = await runRepository.DeleteImportedBuildAsync(id, cancellationToken);
        if (deleted)
        {
            await RefreshImportedBuildsAsync(cancellationToken);
            Notify();
        }

        return deleted;
    }

    private HonorRun CreateDefaultRun(string name)
    {
        var run = new HonorRun
        {
            Name = name,
            CreatedAt = DateTimeOffset.UtcNow,
            GuideVersion = Guide.GuideVersion,
        };
        run.NormalizeRoster();
        return run;
    }

    private async Task<AppPreferences> LoadPreferencesAsync(
        CancellationToken cancellationToken)
    {
        var value = await runRepository.GetSettingAsync(
            PreferencesKey,
            cancellationToken);
        if (value is null)
        {
            return new AppPreferences();
        }

        try
        {
            return JsonSerializer.Deserialize<AppPreferences>(value, json) ?? new();
        }
        catch (JsonException)
        {
            return new AppPreferences();
        }
    }

    private async Task RefreshRunsAsync(CancellationToken cancellationToken)
    {
        Runs = await runRepository.ListAsync(cancellationToken);
    }

    private async Task RefreshImportedBuildsAsync(CancellationToken cancellationToken)
    {
        importedBuilds.Clear();
        foreach (var value in await runRepository.ListImportedBuildJsonAsync(cancellationToken))
        {
            try
            {
                if (JsonSerializer.Deserialize<ImportedBuild>(value, json) is { } imported)
                {
                    importedBuilds.Add(imported);
                }
            }
            catch (JsonException)
            {
                RecoveryNotice ??=
                    "One saved imported build was unreadable and was not loaded.";
            }
        }
    }

    private bool SnapshotIsValid(string snapshot)
    {
        try
        {
            _ = DeserializeRun(snapshot);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private HonorRun DeserializeRun(string snapshot) =>
        JsonSerializer.Deserialize<HonorRun>(snapshot, json) ??
        throw new JsonException("Run snapshot decoded to null.");

    private IReadOnlyDictionary<string, CheckpointDisposition> CheckpointDispositions()
    {
        var result = new Dictionary<string, CheckpointDisposition>(StringComparer.Ordinal);
        foreach (var step in Walkthrough.Where(step => step.CheckpointId is not null))
        {
            result[step.CheckpointId!] = RunSafety.WalkthroughDisposition(
                step,
                Run.WalkthroughProgress ?? EmptyProgress);
        }

        return result;
    }

    private IReadOnlySet<string> CompletedCheckpointIds() =>
        CheckpointDispositions()
            .Where(pair => pair.Value.CountsAsCompleted())
            .Select(pair => pair.Key)
            .ToHashSet(StringComparer.Ordinal);

    private void SyncRegion()
    {
        if (RunSafety.NextWalkthroughStep(
                Walkthrough,
                Run.WalkthroughProgress ?? EmptyProgress,
                Run.WalkthroughOutcomes,
                LowestPartyLevel) is { } next)
        {
            Run.MapRegion = next.Region;
        }
    }

    private void Notify() => StateChanged?.Invoke(this, EventArgs.Empty);

    private static readonly IReadOnlyDictionary<string, CheckpointDisposition> EmptyProgress =
        new Dictionary<string, CheckpointDisposition>();

    private static readonly IReadOnlyDictionary<string, string> EmptyOutcomes =
        new Dictionary<string, string>();
}
