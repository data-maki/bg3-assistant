namespace BG3HonorAssistant.Core.Models;

public sealed record CheckpointProgress
{
    public HashSet<string> CheckedPreparation { get; init; } = [];

    public HashSet<string> CheckedCompletion { get; init; } = [];

    public string SkipNote { get; init; } = string.Empty;

    public DateTimeOffset UpdatedAt { get; init; } = DateTimeOffset.UtcNow;
}

public enum ActGearReviewStatus
{
    Obtained,
    Missed,
}

public sealed record ActTransitionRecord(
    int FromAct,
    int ToAct,
    IReadOnlyDictionary<string, ActGearReviewStatus> GearReview,
    int UnresolvedRouteCount,
    DateTimeOffset AdvancedAt,
    IReadOnlyList<BuildGear>? Gear = null);

public sealed record PartyPlan(
    IReadOnlyList<PartyMember> Roster,
    IReadOnlyDictionary<string, HashSet<string>> EquippedByMember,
    IReadOnlyDictionary<string, DateTimeOffset> BuildAssignedAt,
    IReadOnlyDictionary<string, string> GearAssignmentOverrides,
    IReadOnlyDictionary<string, Dictionary<string, string>> PlannedSlotOverrides,
    GearTarget? GearTarget);

public sealed class HonorRun
{
    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string? Name { get; set; }

    public DateTimeOffset? CreatedAt { get; set; }

    public RunDifficulty? Difficulty { get; set; }

    public RouteRevealPolicy? RouteRevealPolicy { get; set; }

    public string GuideVersion { get; set; } = string.Empty;

    public List<PartyMember> Party { get; set; } =
    [
        Member("tav", "Tav", null),
        Member("companion-1", "Shadowheart", "Cleric"),
        Member("companion-2", "Lae'zel", "Fighter"),
        Member("companion-3", "Astarion", "Rogue"),
    ];

    public List<PartyMember>? Roster { get; set; }

    public HashSet<string>? StoryOutcomes { get; set; }

    public bool? IncludeCampPlans { get; set; }

    public Dictionary<string, HashSet<string>>? EquippedByMember { get; set; }

    public bool? EquipmentOwnershipKnown { get; set; }

    public Dictionary<string, DateTimeOffset>? BuildAssignedAt { get; set; }

    public Dictionary<string, string>? GearAssignmentOverrides { get; set; }

    public Dictionary<string, Dictionary<string, string>>? PlannedSlotOverrides { get; set; }

    public Dictionary<string, CheckpointProgress> Progress { get; set; } = [];

    public Dictionary<string, CheckpointDisposition>? WalkthroughProgress { get; set; }

    public Dictionary<string, string>? WalkthroughOutcomes { get; set; }

    public string? FocusedWalkthroughStepId { get; set; }

    public GearTarget? GearTarget { get; set; }

    public string? SelectedCheckpointId { get; set; }

    public int? SelectedAct { get; set; } = 1;

    public Dictionary<int, Dictionary<string, ActGearReviewStatus>>? ActGearReview { get; set; }

    public List<ActTransitionRecord>? ActTransitions { get; set; }

    public ActTransitionRecord? FinalActRecord { get; set; }

    public string MapRegion { get; set; } = "Wilderness";

    public HashSet<string>? MutedCheckpointIds { get; set; }

    public void NormalizeRoster()
    {
        if (SelectedAct is < 1 or > 3 or null)
        {
            SelectedAct = 1;
        }

        Difficulty ??= RunDifficulty.Balanced;
        RouteRevealPolicy ??= Models.RouteRevealPolicy.Everything;

        var hadRoster = Roster is not null;
        var members = (Roster ?? Party).ToList();
        for (var index = 0; index < members.Count; index++)
        {
            var member = members[index];
            var isCustom = member.IsCustom ?? member.Id == "tav" || index == 0;
            members[index] = member with
            {
                Status = hadRoster ? member.Status : RosterStatus.Active,
                IsCustom = isCustom,
                AbilityScores = member.AbilityScores ??
                                (isCustom
                                    ? Models.AbilityScores.CustomDefault
                                    : Models.AbilityScores.ForClass(member.ClassName)),
                IsHireling = member.IsHireling ?? false,
            };
        }

        var existingNames = members
            .Select(member => member.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var recruitableNames = StoryCompanionCatalog.Recruitable
            .Select(companion => companion.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var companion in StoryCompanionCatalog.All)
        {
            if (existingNames.Contains(companion.Name))
            {
                continue;
            }

            var stableId = companion.Name
                .Replace("'", string.Empty, StringComparison.Ordinal)
                .Replace(' ', '-')
                .ToLowerInvariant();
            members.Add(
                new PartyMember
                {
                    Id = stableId,
                    Name = companion.Name,
                    Level = Party.Count == 0 ? 1 : Party.Max(member => member.Level),
                    ClassName = companion.DefaultClass,
                    Status = recruitableNames.Contains(companion.Name)
                        ? RosterStatus.Unrecruited
                        : RosterStatus.Camp,
                    PreparedTags = [],
                    IsCustom = false,
                    AbilityScores = Models.AbilityScores.ForClass(companion.DefaultClass),
                    IsHireling = false,
                });
        }

        var activeCount = 0;
        for (var index = 0; index < members.Count; index++)
        {
            if (members[index].RosterStatus != RosterStatus.Active)
            {
                continue;
            }

            activeCount++;
            if (activeCount > 4)
            {
                members[index] = members[index] with { Status = RosterStatus.Camp };
            }
        }

        Roster = members;
        SyncActivePartyProjection();
        StoryOutcomes ??= [];
        IncludeCampPlans ??= false;
        EquippedByMember ??= [];
        EquipmentOwnershipKnown ??= false;
        BuildAssignedAt ??= members
            .Where(member => member.BuildId is not null)
            .ToDictionary(member => member.Id, _ => DateTimeOffset.UnixEpoch);
        GearAssignmentOverrides ??= [];
        PlannedSlotOverrides ??= [];
        ActGearReview ??= [];
        ActTransitions ??= [];
    }

    public void SyncActivePartyProjection()
    {
        Party = (Roster ?? Party)
            .Where(member => member.RosterStatus == RosterStatus.Active)
            .Take(4)
            .ToList();
    }

    public HonorRun FreshRun(
        string name,
        string guideVersion,
        IReadOnlyList<BuildSummary> availableBuilds,
        DateTimeOffset createdAt)
    {
        NormalizeRoster();
        var fresh = new HonorRun();
        fresh.NormalizeRoster();
        fresh.Name = name;
        fresh.CreatedAt = createdAt;
        fresh.GuideVersion = guideVersion;
        fresh.Difficulty = Difficulty;
        fresh.RouteRevealPolicy = RouteRevealPolicy;

        var buildsById = availableBuilds.ToDictionary(build => build.Id);
        var defaultMembers = fresh.Roster!.ToDictionary(member => member.Id);
        fresh.Roster = Roster!
            .Select(
                member =>
                {
                    BuildSummary? build = null;
                    var hasBuild = member.BuildId is not null &&
                                   buildsById.TryGetValue(member.BuildId, out build);
                    defaultMembers.TryGetValue(member.Id, out var defaultMember);
                    var status = member.RosterStatus is
                        RosterStatus.Active or RosterStatus.Camp or RosterStatus.Unrecruited
                            ? member.RosterStatus
                            : defaultMember?.RosterStatus ?? RosterStatus.Camp;
                    var className = hasBuild
                        ? build!.AbilitySetups?
                              .OrderBy(setup => setup.Level)
                              .FirstOrDefault()?.FirstClass ??
                          build.Levels.OrderBy(level => level.Level).FirstOrDefault()?.Take
                        : defaultMember?.ClassName ?? member.ClassName;
                    var scores = hasBuild
                        ? build!.StartingAbilityScores
                        : member.IsCustom == true
                            ? Models.AbilityScores.CustomDefault
                            : Models.AbilityScores.ForClass(className);

                    return member with
                    {
                        Level = 1,
                        BuildId = hasBuild ? build!.Id : null,
                        PreparedTags = [],
                        ClassName = className,
                        Status = status,
                        AbilityScores = scores,
                        SourceLoadoutId = null,
                        AbilityModifiers = [],
                        UsesBuildAbilityScores = hasBuild,
                        AppliedAbilitySetupId = null,
                        ManualBuild = hasBuild ? null : member.ManualBuild,
                    };
                })
            .ToList();
        fresh.BuildAssignedAt = fresh.Roster
            .Where(member => member.BuildId is not null)
            .ToDictionary(member => member.Id, _ => createdAt);
        fresh.SyncActivePartyProjection();
        return fresh;
    }

    public bool ActLedgerIsLocked(int act) =>
        act < (SelectedAct ?? 1) || (act == 3 && FinalActRecord is not null);

    public ActTransitionRecord? LockedActRecord(int act)
    {
        if (!ActLedgerIsLocked(act))
        {
            return null;
        }

        return act == 3
            ? FinalActRecord
            : ActTransitions?.FirstOrDefault(transition => transition.FromAct == act);
    }

    public ActGearReviewStatus? LockedActGearReviewStatus(string itemKey, int act)
    {
        var record = LockedActRecord(act);
        return record is not null &&
               record.GearReview.TryGetValue(itemKey, out var status)
            ? status
            : null;
    }

    public PartyPlan GetPartyPlan()
    {
        NormalizeRoster();
        return new PartyPlan(
            Roster!.ToList(),
            EquippedByMember!.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ToHashSet(StringComparer.Ordinal)),
            new Dictionary<string, DateTimeOffset>(BuildAssignedAt!),
            new Dictionary<string, string>(GearAssignmentOverrides!),
            PlannedSlotOverrides!.ToDictionary(
                pair => pair.Key,
                pair => new Dictionary<string, string>(pair.Value)),
            GearTarget);
    }

    public void ApplyPartyPlan(PartyPlan plan)
    {
        Roster = plan.Roster.ToList();
        EquippedByMember = plan.EquippedByMember.ToDictionary(
            pair => pair.Key,
            pair => pair.Value.ToHashSet(StringComparer.Ordinal));
        BuildAssignedAt = new Dictionary<string, DateTimeOffset>(
            plan.BuildAssignedAt);
        GearAssignmentOverrides = new Dictionary<string, string>(
            plan.GearAssignmentOverrides);
        PlannedSlotOverrides = plan.PlannedSlotOverrides.ToDictionary(
            pair => pair.Key,
            pair => new Dictionary<string, string>(pair.Value));
        GearTarget = plan.GearTarget;
        SyncActivePartyProjection();
    }

    public bool ApplyRosterStatus(RosterStatus status, string memberId)
    {
        NormalizeRoster();
        var index = Roster!.FindIndex(member => member.Id == memberId);
        if (index < 0)
        {
            return false;
        }

        var current = Roster[index].RosterStatus;
        if (status == RosterStatus.Active)
        {
            if (!current.CanBeActive() ||
                Roster.Count(
                    member =>
                        member.Id != memberId &&
                        member.RosterStatus == RosterStatus.Active) >= 4)
            {
                return false;
            }
        }

        Roster[index] = Roster[index] with { Status = status };
        SyncActivePartyProjection();
        return true;
    }

    public string? EquipmentOwnerId(string itemKey) =>
        EquippedByMember?
            .FirstOrDefault(pair => pair.Value.Contains(itemKey))
            .Key;

    public bool ToggleEquipment(string itemKey, string memberId)
    {
        NormalizeRoster();
        if (!Roster!.Any(member => member.Id == memberId))
        {
            return false;
        }

        var alreadyAssigned =
            EquippedByMember!.TryGetValue(memberId, out var owned) &&
            owned.Contains(itemKey);
        foreach (var ownerId in EquippedByMember.Keys.ToArray())
        {
            EquippedByMember[ownerId].Remove(itemKey);
            if (EquippedByMember[ownerId].Count == 0)
            {
                EquippedByMember.Remove(ownerId);
            }
        }

        if (!alreadyAssigned)
        {
            if (!EquippedByMember.TryGetValue(memberId, out var assignments))
            {
                assignments = [];
                EquippedByMember[memberId] = assignments;
            }

            assignments.Add(itemKey);
        }

        EquipmentOwnershipKnown = true;
        return true;
    }

    public void SetStoryOutcome(string outcome, bool confirmed)
    {
        StoryOutcomes ??= [];
        if (confirmed)
        {
            StoryOutcomes.Add(outcome);
        }
        else
        {
            StoryOutcomes.Remove(outcome);
        }
    }

    public void FocusRoute(string? stepId, string? checkpointId)
    {
        GearTarget = null;
        FocusedWalkthroughStepId = stepId;
        SelectedCheckpointId = checkpointId;
    }

    public void FocusGear(GearTarget target)
    {
        GearTarget = target;
        FocusedWalkthroughStepId = null;
        SelectedCheckpointId = null;
    }

    private static PartyMember Member(string id, string name, string? className) =>
        new()
        {
            Id = id,
            Name = name,
            Level = 1,
            ClassName = className,
            PreparedTags = [],
        };
}
