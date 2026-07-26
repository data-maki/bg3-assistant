using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
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

    public async Task SetAllPartyLevelsAsync(
        int level,
        CancellationToken cancellationToken = default)
    {
        Run.NormalizeRoster();
        for (var index = 0; index < Run.Roster!.Count; index++)
        {
            Run.Roster[index] = PartyPlanningRules.AtLevel(
                Run.Roster[index],
                Math.Clamp(level, 1, 12),
                Builds);
        }

        Run.SyncActivePartyProjection();
        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> SelectOnboardingActAsync(
        int act,
        CancellationToken cancellationToken = default)
    {
        if (act is < 1 or > 3 || !Guide.Payloads.ContainsKey(act.ToString()))
        {
            return false;
        }

        Run.SelectedAct = act;
        Run.SelectedCheckpointId = null;
        Run.FocusedWalkthroughStepId = null;
        Run.MapRegion =
            Guide.Payloads[act.ToString()].Acts
                .FirstOrDefault(summary => summary.Act == act)?.Title ??
            $"Act {act}";
        await SaveAsync(cancellationToken);
        Notify();
        return true;
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

    public async Task<bool> ResetCharacterPlanAsync(
        string memberId,
        CancellationToken cancellationToken = default)
    {
        if (!PartyPlanningRules.Respec(Run, memberId))
        {
            return false;
        }

        _ = PartyPlanningRules.ValidateGearTarget(Run, Builds, Guide.Items);
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> BeginManualBuildAsync(
        string memberId,
        CancellationToken cancellationToken = default)
    {
        Run.NormalizeRoster();
        var index = Run.Roster!.FindIndex(member => member.Id == memberId);
        if (index < 0)
        {
            return false;
        }

        var member = Run.Roster[index];
        if (member.ManualBuild is not null)
        {
            return true;
        }

        var plan = ManualBuildPlan.Empty(
            $"{member.Name}'s Build",
            member.EffectiveAbilityScores.ClampedForPointBuy);
        var startingClass = ClassCatalog.Definitions.FirstOrDefault(
            definition =>
                string.Equals(
                    member.ClassName,
                    definition.Name,
                    StringComparison.Ordinal) ||
                member.ClassName?.StartsWith(
                    definition.Name + " ",
                    StringComparison.Ordinal) == true)?.Name;
        if (startingClass is not null)
        {
            plan.SetClass(startingClass, 1);
        }

        Run.Roster[index] = member with
        {
            BuildId = null,
            ManualBuild = plan,
            AbilityScores = plan.AbilityScores,
            UsesBuildAbilityScores = false,
            AppliedAbilitySetupId = null,
        };
        Run.BuildAssignedAt?.Remove(member.Id);
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<bool> RenameManualBuildAsync(
        string memberId,
        string name,
        CancellationToken cancellationToken = default)
    {
        if (ManualMember(memberId) is not { } selection)
        {
            return false;
        }

        Run.Roster![selection.Index] = selection.Member with
        {
            ManualBuild = selection.Member.ManualBuild! with
            {
                Name = string.IsNullOrWhiteSpace(name)
                    ? $"{selection.Member.Name}'s Build"
                    : name.Trim(),
            },
        };
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<bool> SetManualAbilityAsync(
        string memberId,
        Ability ability,
        int value,
        CancellationToken cancellationToken = default)
    {
        if (ManualMember(memberId) is not { } selection)
        {
            return false;
        }

        var scores = selection.Member.ManualBuild!.AbilityScores;
        value = Math.Clamp(value, 8, 15);
        scores = ability switch
        {
            Ability.Strength => scores with { Strength = value },
            Ability.Dexterity => scores with { Dexterity = value },
            Ability.Constitution => scores with { Constitution = value },
            Ability.Intelligence => scores with { Intelligence = value },
            Ability.Wisdom => scores with { Wisdom = value },
            Ability.Charisma => scores with { Charisma = value },
            _ => scores,
        };
        Run.Roster![selection.Index] = selection.Member with
        {
            ManualBuild = selection.Member.ManualBuild with
            {
                AbilityScores = scores,
            },
            AbilityScores = scores,
            UsesBuildAbilityScores = false,
        };
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<bool> SetManualClassAsync(
        string memberId,
        int characterLevel,
        string className,
        CancellationToken cancellationToken = default)
    {
        if (ManualMember(memberId) is not { } selection ||
            !ClassCatalog.Definitions.Any(
                definition => definition.Name == className))
        {
            return false;
        }

        var plan = selection.Member.ManualBuild!;
        var firstClass = plan.Levels.FirstOrDefault()?.ClassName;
        if (Run.Difficulty == RunDifficulty.Explorer &&
            !string.IsNullOrWhiteSpace(firstClass) &&
            className != firstClass)
        {
            return false;
        }

        plan.SetClass(className, characterLevel);
        Run.Roster![selection.Index] = selection.Member with
        {
            BuildId = null,
            ManualBuild = plan,
            ClassName = string.IsNullOrWhiteSpace(plan.ClassSummary)
                ? null
                : plan.ClassSummary,
            UsesBuildAbilityScores = false,
        };
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<bool> ToggleManualChoiceAsync(
        string memberId,
        int characterLevel,
        BuildChoiceGroup group,
        string option,
        CancellationToken cancellationToken = default)
    {
        if (ManualMember(memberId) is not { } selection)
        {
            return false;
        }

        var plan = selection.Member.ManualBuild!;
        var level = plan.Levels.FirstOrDefault(
            candidate => candidate.CharacterLevel == characterLevel);
        if (level is null || group.Options.All(candidate => candidate.Name != option))
        {
            return false;
        }

        var selected = level.Selections.GetValueOrDefault(group.Id)?.ToList() ?? [];
        if (!selected.Remove(option))
        {
            if (selected.Count >= group.MaximumSelections && selected.Count > 0)
            {
                selected.RemoveAt(0);
            }

            selected.Add(option);
        }

        level.Selections[group.Id] = selected;
        Run.Roster![selection.Index] = selection.Member with { ManualBuild = plan };
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<bool> ApplyAbilitySetupAsync(
        string memberId,
        AbilitySetupPlan setup,
        CancellationToken cancellationToken = default)
    {
        Run.NormalizeRoster();
        var index = Run.Roster!.FindIndex(member => member.Id == memberId);
        if (index < 0 || !AbilityProgression.IsValidBg3Setup(setup))
        {
            return false;
        }

        Run.Roster[index] = Run.Roster[index] with
        {
            AbilityScores = setup.FinalScores,
            UsesBuildAbilityScores = true,
            AppliedAbilitySetupId = setup.Id,
        };
        await SavePartyEditAsync(cancellationToken);
        return true;
    }

    public async Task<string?> SetAbilitySourceAsync(
        string memberId,
        AbilityPlanSource source,
        bool applied,
        CancellationToken cancellationToken = default)
    {
        if (!AbilitySourceRules.TrySet(
                Run,
                source,
                applied,
                memberId,
                Run.SelectedAct ?? 1,
                out var error))
        {
            return error ?? "That ability source cannot be changed here.";
        }

        await SavePartyEditAsync(cancellationToken);
        return null;
    }

    private (int Index, PartyMember Member)? ManualMember(string memberId)
    {
        Run.NormalizeRoster();
        var index = Run.Roster!.FindIndex(member => member.Id == memberId);
        return index >= 0 && Run.Roster[index].ManualBuild is not null
            ? (index, Run.Roster[index])
            : null;
    }

    private async Task SavePartyEditAsync(CancellationToken cancellationToken)
    {
        Run.SyncActivePartyProjection();
        _ = PartyPlanningRules.ValidateGearTarget(Run, Builds, Guide.Items);
        SyncRegion();
        await SaveAsync(cancellationToken);
        Notify();
    }
}
