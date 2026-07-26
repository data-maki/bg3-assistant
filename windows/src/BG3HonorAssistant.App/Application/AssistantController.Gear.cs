using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    public async Task<bool> SetSlotOverrideAsync(
        string memberId,
        DollCell cell,
        string? itemKey,
        CancellationToken cancellationToken = default)
    {
        var member = ActiveParty.FirstOrDefault(candidate => candidate.Id == memberId);
        if (member is null)
        {
            return false;
        }

        if (itemKey is not null)
        {
            var item = Guide.Items.FirstOrDefault(candidate => candidate.ItemKey == itemKey);
            if (item is null ||
                item.Act > (Run.SelectedAct ?? 1) ||
                LoadoutSlotClassifier.Classify(item.Slot, item.Name) != cell.Slot)
            {
                return false;
            }
        }

        PartyPlanningRules.SetSlotOverride(
            Run,
            member,
            cell,
            itemKey,
            Guide.Items);
        _ = PartyPlanningRules.ValidateGearTarget(Run, Builds, Guide.Items);
        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> SetGearAssignmentOverrideAsync(
        BuildGear gear,
        string memberId,
        CancellationToken cancellationToken = default)
    {
        var member = ActiveParty.FirstOrDefault(candidate => candidate.Id == memberId);
        if (member is null ||
            !PartyPlanningRules.WantedGear(
                    Run,
                    member,
                    Run.SelectedAct ?? 1,
                    Builds,
                    Guide.Items)
                .Any(candidate => candidate.ItemKey == gear.ItemKey))
        {
            return false;
        }

        PartyPlanningRules.SetGearAssignmentOverride(Run, gear, memberId);
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

    public async Task<bool> ToggleGearEquippedAsync(
        string memberId,
        BuildGear gear,
        CancellationToken cancellationToken = default)
    {
        if (!gear.IsMapObjective ||
            ActiveParty.All(member => member.Id != memberId) ||
            !Run.ToggleEquipment(gear.ItemKey, memberId))
        {
            return false;
        }

        if (Run.GearTarget is { } target &&
            target.MemberId == memberId &&
            target.GearId == gear.Id &&
            Run.EquipmentOwnerId(gear.ItemKey) == memberId)
        {
            Run.GearTarget = null;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }
}
