namespace BG3HonorAssistant.Core.Models;

public static class AbilitySourceRules
{
    public static bool IsApplied(
        AbilityPlanSource source,
        PartyMember member,
        IReadOnlySet<string> equippedItemKeys)
    {
        if (source.Kind == AbilityPlanSourceKind.Equipment &&
            source.ItemKey is { } itemKey)
        {
            return equippedItemKeys.Contains(itemKey);
        }

        return (member.AbilityModifiers ?? []).Any(
            modifier =>
                modifier.PlanSourceId == source.Id ||
                (modifier.PlanSourceId is null &&
                 modifier.Source == source.Label));
    }

    public static PartyMember? Owner(
        AbilityPlanSource source,
        IReadOnlyList<PartyMember> roster,
        IReadOnlyDictionary<string, HashSet<string>> equippedByMember)
    {
        if (!source.UniqueAcrossParty)
        {
            return null;
        }

        if (source.Kind == AbilityPlanSourceKind.Equipment &&
            source.ItemKey is { } itemKey)
        {
            var memberId = equippedByMember.FirstOrDefault(
                pair => pair.Value.Contains(itemKey)).Key;
            return memberId is null
                ? null
                : roster.FirstOrDefault(member => member.Id == memberId);
        }

        return roster.FirstOrDefault(
            member =>
                (member.AbilityModifiers ?? []).Any(
                    modifier => modifier.Source == source.Label));
    }

    public static bool TrySet(
        HonorRun run,
        AbilityPlanSource source,
        bool applied,
        string memberId,
        int selectedAct,
        out string? error)
    {
        ArgumentNullException.ThrowIfNull(run);
        error = null;
        if (source.Kind is not (
                AbilityPlanSourceKind.Permanent or
                AbilityPlanSourceKind.Consumable))
        {
            return false;
        }

        run.NormalizeRoster();
        var memberIndex = run.Roster!.FindIndex(member => member.Id == memberId);
        if (memberIndex < 0)
        {
            return false;
        }

        var member = run.Roster[memberIndex];
        if (applied &&
            (selectedAct < source.MinimumAct ||
             member.Level < source.MinimumLevel))
        {
            error =
                $"{source.Label} is planned for Act {source.MinimumAct}, " +
                $"level {source.MinimumLevel} or later.";
            return false;
        }

        if (source.UniqueAcrossParty && applied)
        {
            for (var index = 0; index < run.Roster.Count; index++)
            {
                run.Roster[index] = run.Roster[index] with
                {
                    AbilityModifiers = (run.Roster[index].AbilityModifiers ?? [])
                        .Where(modifier => modifier.Source != source.Label)
                        .ToList(),
                };
            }
        }

        var modifiers = (run.Roster[memberIndex].AbilityModifiers ?? [])
            .Where(
                modifier =>
                    modifier.PlanSourceId != source.Id &&
                    modifier.Source != source.Label)
            .ToList();
        if (source.Kind == AbilityPlanSourceKind.Consumable && applied)
        {
            modifiers.RemoveAll(
                modifier => modifier.Kind == AbilityModifierKind.Temporary);
        }

        if (applied)
        {
            modifiers.Add(
                new AbilityModifier(
                    source.Ability,
                    source.Kind == AbilityPlanSourceKind.Permanent
                        ? AbilityModifierKind.Permanent
                        : AbilityModifierKind.Temporary,
                    source.Mode,
                    source.Value,
                    source.Label)
                {
                    PlanSourceId = source.Id,
                });
        }

        run.Roster[memberIndex] = run.Roster[memberIndex] with
        {
            AbilityModifiers = modifiers,
        };
        run.SyncActivePartyProjection();
        return true;
    }
}
