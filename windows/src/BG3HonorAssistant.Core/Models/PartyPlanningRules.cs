using System.Text.RegularExpressions;

namespace BG3HonorAssistant.Core.Models;

public sealed record PartyRuleResult(bool Applied, string? Error = null);

public sealed record GearConflict(bool Mine, string Short, string Detail);

public static partial class PartyPlanningRules
{
    public static PartyRuleResult AddHireling(HonorRun run, WithersHireling hireling)
    {
        var members = EnsureRoster(run);
        if (members.Any(
                member =>
                    string.Equals(
                        member.Name,
                        hireling.Name,
                        StringComparison.OrdinalIgnoreCase)))
        {
            return new(false, $"{hireling.Name} is already in this run.");
        }

        if (members.Count(member => member.IsHireling == true) >= 3)
        {
            return new(false, "Withers allows up to three hirelings in a run.");
        }

        var lowestPartyLevel = run.Party.Count == 0
            ? 1
            : run.Party.Min(member => member.Level);
        members.Add(
            new PartyMember
            {
                Id = "hireling-" + SlugCharacters()
                    .Replace(hireling.Name.ToLowerInvariant(), "-")
                    .Trim('-'),
                Name = hireling.Name,
                Level = Math.Max(3, lowestPartyLevel),
                PreparedTags = [],
                ClassName = hireling.DefaultClass,
                Status = RosterStatus.Camp,
                IsCustom = false,
                AbilityScores = hireling.DefaultAbilityScores,
                IsHireling = true,
            });
        run.SyncActivePartyProjection();
        return new(true);
    }

    public static PartyRuleResult RemoveHireling(HonorRun run, string memberId)
    {
        var roster = EnsureRoster(run);
        var index = roster.FindIndex(member => member.Id == memberId);
        if (index < 0 || roster[index].IsHireling != true)
        {
            return new(false, "Could not find that hireling in this run.");
        }

        var member = roster[index];
        if (member.RosterStatus == RosterStatus.Active)
        {
            return new(
                false,
                $"Send {member.Name} to the inactive roster before replacing them.");
        }

        roster.RemoveAt(index);
        run.EquippedByMember?.Remove(member.Id);
        run.BuildAssignedAt?.Remove(member.Id);
        run.PlannedSlotOverrides?.Remove(member.Id);
        run.GearAssignmentOverrides = run.GearAssignmentOverrides?
            .Where(pair => pair.Value != member.Id)
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal);
        if (run.GearTarget?.MemberId == member.Id)
        {
            run.GearTarget = null;
        }

        run.SyncActivePartyProjection();
        return new(true);
    }

    public static bool Respec(HonorRun run, string memberId)
    {
        var roster = EnsureRoster(run);
        var index = roster.FindIndex(member => member.Id == memberId);
        if (index < 0)
        {
            return false;
        }

        var member = roster[index];
        var defaultClass =
            WithersHirelingCatalog.Matching(member.Name)?.DefaultClass ??
            StoryCompanionCatalog.Matching(member.Name)?.DefaultClass ??
            member.ClassName;
        roster[index] = member with
        {
            BuildId = null,
            ClassName = member.IsCustom == true ? null : defaultClass,
            PreparedTags = [],
            RoleOverride = null,
            AbilityScores = member.IsCustom == true
                ? Models.AbilityScores.CustomDefault
                : Models.AbilityScores.ForClass(defaultClass),
            AbilityModifiers = [],
            UsesBuildAbilityScores = false,
            AppliedAbilitySetupId = null,
            SourceLoadoutId = null,
            ManualBuild = null,
        };
        run.EquippedByMember?.Remove(member.Id);
        run.BuildAssignedAt?.Remove(member.Id);
        run.PlannedSlotOverrides?.Remove(member.Id);
        run.GearAssignmentOverrides = run.GearAssignmentOverrides?
            .Where(pair => pair.Value != member.Id)
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal);
        run.SyncActivePartyProjection();
        return true;
    }

    public static PartyRuleResult SwapIntoActive(
        HonorRun run,
        string memberId,
        string activeMemberId)
    {
        var roster = EnsureRoster(run);
        var incoming = roster.FindIndex(member => member.Id == memberId);
        var outgoing = roster.FindIndex(member => member.Id == activeMemberId);
        if (incoming < 0 ||
            outgoing < 0 ||
            !roster[incoming].RosterStatus.CanBeActive() ||
            roster[incoming].RosterStatus == RosterStatus.Active ||
            roster[outgoing].RosterStatus != RosterStatus.Active)
        {
            return new(
                false,
                "Only a Camp or unrecruited member can replace an active party member.");
        }

        var incomingMember = roster[incoming] with { Status = RosterStatus.Active };
        var outgoingMember = roster[outgoing] with { Status = RosterStatus.Camp };
        roster[outgoing] = incomingMember;
        roster[incoming] = outgoingMember;
        run.SyncActivePartyProjection();
        return new(true);
    }

    public static PartyMember AtLevel(
        PartyMember member,
        int level,
        IReadOnlyList<BuildSummary> builds)
    {
        var className = member.ClassName;
        if (member.ManualBuild is { ClassSummary.Length: > 0 } manual)
        {
            className = manual.ClassSummary;
        }
        else if (member.BuildId is { } buildId &&
                 builds.FirstOrDefault(build => build.Id == buildId) is { } build &&
                 build.Levels.LastOrDefault(plan => plan.Level <= level) is { } plan)
        {
            className = plan.Take;
        }

        return member with { Level = level, ClassName = className };
    }

    public static bool BuildReplacementNeedsConfirmation(
        HonorRun run,
        PartyMember member) =>
        member.BuildId is not null &&
        ((member.AbilityModifiers ?? [])
             .Any(modifier => modifier.Kind != AbilityModifierKind.Permanent) ||
         (run.EquippedByMember?.GetValueOrDefault(member.Id)?.Count ?? 0) > 0 ||
         member.AppliedAbilitySetupId is not null);

    public static bool AssignBuild(
        HonorRun run,
        string memberId,
        string? buildId,
        IReadOnlyList<BuildSummary> builds,
        DateTimeOffset assignedAt)
    {
        var roster = EnsureRoster(run);
        var index = roster.FindIndex(member => member.Id == memberId);
        if (index < 0)
        {
            return false;
        }

        var current = roster[index];
        var copy = current with
        {
            BuildId = buildId,
            ManualBuild = buildId is null ? current.ManualBuild : null,
            AppliedAbilitySetupId = null,
        };
        if (buildId is null)
        {
            run.BuildAssignedAt?.Remove(memberId);
            run.PlannedSlotOverrides?.Remove(memberId);
        }
        else if (buildId != current.BuildId)
        {
            run.BuildAssignedAt ??= [];
            run.BuildAssignedAt[memberId] = assignedAt;
            run.PlannedSlotOverrides?.Remove(memberId);
        }

        var build = buildId is null
            ? null
            : builds.FirstOrDefault(candidate => candidate.Id == buildId);
        if (build is not null &&
            build.Levels.LastOrDefault(level => level.Level <= copy.Level) is { } plan)
        {
            copy = copy with { ClassName = plan.Take };
        }

        copy = copy with
        {
            AbilityModifiers = (copy.AbilityModifiers ?? [])
                .Where(modifier => modifier.Kind == AbilityModifierKind.Permanent)
                .ToList(),
            UsesBuildAbilityScores = build is not null,
        };
        roster[index] = copy;
        run.SyncActivePartyProjection();
        return true;
    }

    public static bool ApplyAbilitySetup(
        HonorRun run,
        string memberId,
        AbilitySetupPlan setup)
    {
        var roster = EnsureRoster(run);
        var index = roster.FindIndex(member => member.Id == memberId);
        if (index < 0)
        {
            return false;
        }

        roster[index] = roster[index] with
        {
            AbilityScores = setup.FinalScores,
            UsesBuildAbilityScores = true,
            AppliedAbilitySetupId = setup.Id,
        };
        run.SyncActivePartyProjection();
        return true;
    }

    public static IReadOnlyList<BuildGear> WantedGear(
        HonorRun run,
        PartyMember member,
        int act,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        if (member.BuildId is null ||
            builds.FirstOrDefault(build => build.Id == member.BuildId) is not { } build)
        {
            return [];
        }

        var gear = build.Gear
            .Where(item => item.Act == act && item.IsAvailableAt(member.Level))
            .ToList();
        var catalog = itemCatalog.ToDictionary(
            item => item.ItemKey,
            StringComparer.Ordinal);
        var replacements = (run.PlannedSlotOverrides?.GetValueOrDefault(member.Id) ?? [])
            .Select(
                pair =>
                {
                    if (!catalog.TryGetValue(pair.Value, out var item) || item.Act > act)
                    {
                        return default((string Key, ItemSummary Item)?);
                    }

                    var slot = LoadoutSlotClassifier.Classify(item.Slot, item.Name);
                    var key = slot == LoadoutSlot.Rings &&
                              pair.Key.StartsWith(
                                  slot.Id() + "#",
                                  StringComparison.Ordinal)
                        ? pair.Key
                        : slot == LoadoutSlot.Rings
                            ? slot.Id() + "#0"
                            : slot.Id();
                    return (key, item);
                })
            .Where(replacement => replacement is not null)
            .Select(replacement => replacement!.Value)
            .OrderBy(replacement => replacement.Key, StringComparer.Ordinal)
            .ToList();

        foreach (var (key, item) in replacements)
        {
            var replacement = Route.ActTransitionRules.SyntheticGear(item);
            var slot = LoadoutSlotClassifier.Classify(item.Slot, item.Name);
            if (slot == LoadoutSlot.Rings)
            {
                var separator = key.LastIndexOf('#');
                var field = separator >= 0 &&
                            int.TryParse(key[(separator + 1)..], out var parsed)
                    ? parsed
                    : 0;
                var indices = gear
                    .Select((candidate, index) => (candidate, index))
                    .Where(
                        pair =>
                            LoadoutSlotClassifier.Classify(
                                pair.candidate.Slot,
                                pair.candidate.Item) == LoadoutSlot.Rings)
                    .Select(pair => pair.index)
                    .ToList();
                if (field < indices.Count)
                {
                    gear[indices[field]] = replacement;
                }
                else
                {
                    gear.Add(replacement);
                }
            }
            else
            {
                gear.RemoveAll(
                    candidate =>
                        LoadoutSlotClassifier.Classify(
                            candidate.Slot,
                            candidate.Item) == slot);
                gear.Add(replacement);
            }
        }

        return gear;
    }

    public static IReadOnlyDictionary<string, string> PlannedAssignments(
        HonorRun run,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        var claims = run.Party
            .Select(
                member =>
                {
                    var build = member.BuildId is null
                        ? null
                        : builds.FirstOrDefault(candidate => candidate.Id == member.BuildId);
                    return build is null
                        ? null
                        : new GearClaim(
                            member.Id,
                            member.Name,
                            build.Name,
                            run.BuildAssignedAt?.GetValueOrDefault(member.Id),
                            WantedGear(
                                    run,
                                    member,
                                    run.SelectedAct ?? 1,
                                    builds,
                                    itemCatalog)
                                .Select(gear => gear.ItemKey)
                                .ToHashSet(StringComparer.Ordinal));
                })
            .Where(claim => claim is not null)
            .Cast<GearClaim>()
            .ToList();
        return GearLogic.Assignments(
            claims,
            run.GearAssignmentOverrides ??
            new Dictionary<string, string>(StringComparer.Ordinal));
    }

    public static string? PlannedOwnerId(
        HonorRun run,
        string itemKey,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog) =>
        PlannedAssignments(run, builds, itemCatalog).GetValueOrDefault(itemKey);

    public static void SetGearAssignmentOverride(
        HonorRun run,
        BuildGear gear,
        string memberId)
    {
        run.GearAssignmentOverrides ??= [];
        run.GearAssignmentOverrides[gear.ItemKey] = memberId;
    }

    public static string? SlotOverride(
        HonorRun run,
        PartyMember member,
        DollCell cell,
        IReadOnlyList<ItemSummary> itemCatalog) =>
        ResolvedSlotOverride(run, member, cell, itemCatalog)?.ItemKey;

    public static void SetSlotOverride(
        HonorRun run,
        PartyMember member,
        DollCell cell,
        string? itemKey,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        run.PlannedSlotOverrides ??= [];
        var mine = run.PlannedSlotOverrides.GetValueOrDefault(member.Id) ??
                   new Dictionary<string, string>(StringComparer.Ordinal);
        var existing = ResolvedSlotOverride(run, member, cell, itemCatalog);
        if (existing is not null)
        {
            mine.Remove(existing.Value.Key);
        }

        if (cell.Field == 0)
        {
            mine.Remove(cell.Slot.Id());
        }

        if (itemKey is null)
        {
            mine.Remove(cell.Id);
        }
        else
        {
            mine[cell.Id] = itemKey;
        }

        if (mine.Count == 0)
        {
            run.PlannedSlotOverrides.Remove(member.Id);
        }
        else
        {
            run.PlannedSlotOverrides[member.Id] = mine;
        }
    }

    public static GearConflict? Conflict(
        HonorRun run,
        BuildGear gear,
        PartyMember member,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        var ownerId = run.EquipmentOwnerId(gear.ItemKey);
        if (ownerId is not null &&
            ownerId != member.Id &&
            run.Roster!.FirstOrDefault(candidate => candidate.Id == ownerId) is { } owner)
        {
            return new(
                false,
                $"Equipped by {owner.Name}",
                ConflictDetail(
                    gear,
                    $"{owner.Name} is the player-confirmed owner."));
        }

        var rivals = run.Party
            .Where(
                other =>
                    other.Id != member.Id &&
                    WantedGear(
                            run,
                            other,
                            run.SelectedAct ?? 1,
                            builds,
                            itemCatalog)
                        .Any(candidate => candidate.ItemKey == gear.ItemKey))
            .ToList();
        var plannedOwnerId = PlannedOwnerId(
            run,
            gear.ItemKey,
            builds,
            itemCatalog);
        if (rivals.Count == 0 ||
            plannedOwnerId is null ||
            run.Party.FirstOrDefault(candidate => candidate.Id == plannedOwnerId) is not
                { } planned)
        {
            return null;
        }

        var rivalNames = string.Join(", ", rivals.Select(rival => rival.Name));
        return planned.Id == member.Id
            ? new(
                true,
                $"Also wanted by {rivalNames}",
                ConflictDetail(
                    gear,
                    $"{member.Name}'s build requested it first, so {member.Name} gets it. " +
                    "Open the item to hand it to someone else."))
            : new(
                false,
                $"Assigned to {planned.Name}",
                ConflictDetail(
                    gear,
                    $"{planned.Name}'s build requested it first. " +
                    $"Use “Give to {member.Name}” to override."));
    }

    public static IReadOnlyList<GearPickup> RoutePickups(
        HonorRun run,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        var assignments = PlannedAssignments(run, builds, itemCatalog);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var pickups = new List<GearPickup>();
        foreach (var member in run.Party)
        {
            var wanted = WantedGear(
                    run,
                    member,
                    run.SelectedAct ?? 1,
                    builds,
                    itemCatalog)
                .Where(
                    gear =>
                        gear.Act == (run.SelectedAct ?? 1) &&
                        run.EquipmentOwnerId(gear.ItemKey) is null &&
                        assignments.GetValueOrDefault(gear.ItemKey, member.Id) == member.Id)
                .OrderBy(gear => GearLogic.PriorityRank(gear.Priority))
                .ToList();
            foreach (var gear in wanted)
            {
                var key = $"{member.Id}|{gear.ItemKey}";
                if (seen.Add(key))
                {
                    pickups.Add(new GearPickup(gear, member.Id, member.Name));
                }
            }
        }

        return pickups;
    }

    public static bool ValidateGearTarget(
        HonorRun run,
        IReadOnlyList<BuildSummary> builds,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        if (run.GearTarget is not { } target)
        {
            return true;
        }

        var member = run.Party.FirstOrDefault(candidate => candidate.Id == target.MemberId);
        var valid =
            member is not null &&
            member.BuildId == target.BuildId &&
            WantedGear(
                    run,
                    member,
                    run.SelectedAct ?? 1,
                    builds,
                    itemCatalog)
                .Any(
                    gear =>
                        gear.Id == target.GearId &&
                        gear.Act == (run.SelectedAct ?? 1));
        if (!valid)
        {
            run.GearTarget = null;
        }

        return valid;
    }

    private static (string Key, string ItemKey)? ResolvedSlotOverride(
        HonorRun run,
        PartyMember member,
        DollCell cell,
        IReadOnlyList<ItemSummary> itemCatalog)
    {
        var catalog = itemCatalog.ToDictionary(item => item.ItemKey, StringComparer.Ordinal);
        foreach (var pair in
                 run.PlannedSlotOverrides?.GetValueOrDefault(member.Id) ??
                 new Dictionary<string, string>())
        {
            if (!catalog.TryGetValue(pair.Value, out var item))
            {
                continue;
            }

            var slot = LoadoutSlotClassifier.Classify(item.Slot, item.Name);
            var effectiveId = slot == LoadoutSlot.Rings
                ? pair.Key.StartsWith(slot.Id() + "#", StringComparison.Ordinal)
                    ? pair.Key
                    : slot.Id() + "#0"
                : new DollCell(slot).Id;
            if (effectiveId == cell.Id)
            {
                return (pair.Key, pair.Value);
            }
        }

        return null;
    }

    private static string ConflictDetail(BuildGear gear, string basis) =>
        string.IsNullOrEmpty(gear.Alternative)
            ? $"{basis} No equivalent item is listed; decide ownership before spending gold."
            : $"{basis} Alternative: {gear.Alternative}";

    private static List<PartyMember> EnsureRoster(HonorRun run)
    {
        if (run.Roster is null)
        {
            run.Roster = run.Party.ToList();
        }

        return run.Roster;
    }

    [GeneratedRegex(@"[^a-z0-9]+")]
    private static partial Regex SlugCharacters();
}
