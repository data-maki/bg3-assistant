using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class HonorRunBehaviorTests
{
    [Fact]
    public void NormalizeRosterSeedsEveryCompanionWithOracleStatus()
    {
        var run = new HonorRun();

        run.NormalizeRoster();

        Assert.Equal(12, run.Roster!.Count);
        Assert.Equal(4, run.Party.Count);
        Assert.Equal(
            RosterStatus.Camp,
            run.Roster.Single(member => member.Name == "Dark Urge").RosterStatus);
        Assert.Equal(
            RosterStatus.Camp,
            run.Roster.Single(member => member.Name == "Gale").RosterStatus);
        Assert.Equal(
            RosterStatus.Unrecruited,
            run.Roster.Single(member => member.Name == "Halsin").RosterStatus);
        Assert.False(run.IncludeCampPlans);
        Assert.False(run.EquipmentOwnershipKnown);
        Assert.NotNull(run.GearAssignmentOverrides);
        Assert.NotNull(run.PlannedSlotOverrides);
        Assert.NotNull(run.ActGearReview);
    }

    [Fact]
    public void RosterTransitionsEnforceEligibilityAndFourActiveLimit()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        var gale = run.Roster!.Single(member => member.Name == "Gale");

        Assert.False(run.ApplyRosterStatus(RosterStatus.Active, gale.Id));
        Assert.True(run.ApplyRosterStatus(RosterStatus.Camp, "companion-3"));
        Assert.True(run.ApplyRosterStatus(RosterStatus.Active, gale.Id));
        Assert.Equal(4, run.Party.Count);

        Assert.True(run.ApplyRosterStatus(RosterStatus.Dead, gale.Id));
        Assert.False(run.ApplyRosterStatus(RosterStatus.Active, gale.Id));
    }

    [Fact]
    public void EquipmentAssignmentIsUniqueAndToggleable()
    {
        var run = new HonorRun();
        run.NormalizeRoster();

        Assert.True(run.ToggleEquipment("amulet-of-misty-step", "tav"));
        Assert.Equal("tav", run.EquipmentOwnerId("amulet-of-misty-step"));
        Assert.True(
            run.ToggleEquipment("amulet-of-misty-step", "companion-1"));
        Assert.Equal(
            "companion-1",
            run.EquipmentOwnerId("amulet-of-misty-step"));
        Assert.True(
            run.ToggleEquipment("amulet-of-misty-step", "companion-1"));
        Assert.Null(run.EquipmentOwnerId("amulet-of-misty-step"));
        Assert.True(run.EquipmentOwnershipKnown);
        Assert.False(run.ToggleEquipment("amulet-of-misty-step", "missing"));
    }

    [Fact]
    public void PartyPlanSnapshotRestoresEveryOwnedField()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        run.ToggleEquipment("item-a", "tav");
        run.GearAssignmentOverrides!["item-a"] = "tav";
        run.PlannedSlotOverrides!["tav"] = new() { ["Amulet"] = "item-a" };
        run.GearTarget = new GearTarget("tav", "build-a", "Item A|Region");
        var snapshot = run.GetPartyPlan();

        run.ToggleEquipment("item-b", "companion-1");
        run.GearAssignmentOverrides.Clear();
        run.PlannedSlotOverrides.Clear();
        run.GearTarget = null;
        run.ApplyPartyPlan(snapshot);

        Assert.Equal("tav", run.EquipmentOwnerId("item-a"));
        Assert.Equal("tav", run.GearAssignmentOverrides!["item-a"]);
        Assert.Equal("item-a", run.PlannedSlotOverrides!["tav"]["Amulet"]);
        Assert.Equal(snapshot.GearTarget, run.GearTarget);
    }

    [Fact]
    public void StoryOutcomeCanBeConfirmedAndRemoved()
    {
        var run = new HonorRun();

        run.SetStoryOutcome("saved-grove", true);
        Assert.Contains("saved-grove", run.StoryOutcomes!);

        run.SetStoryOutcome("saved-grove", false);
        Assert.DoesNotContain("saved-grove", run.StoryOutcomes!);
    }
}
