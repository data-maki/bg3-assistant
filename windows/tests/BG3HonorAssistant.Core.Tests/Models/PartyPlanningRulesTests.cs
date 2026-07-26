using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class PartyPlanningRulesTests
{
    [Fact]
    public void CompanionAndHirelingCatalogsMatchTheMacOracle()
    {
        Assert.Equal(7, StoryCompanionCatalog.Origins.Count);
        Assert.Equal(4, StoryCompanionCatalog.Recruitable.Count);
        Assert.Equal(12, WithersHirelingCatalog.All.Count);
        Assert.Equal("Sorcerer", StoryCompanionCatalog.Matching("dark urge")?.DefaultClass);
        Assert.Equal("Wizard", WithersHirelingCatalog.Matching("sir fuzzalump")?.DefaultClass);
    }

    [Fact]
    public void AddHirelingUsesStableIdentityAndOracleLevelFloor()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        run.Roster![0] = run.Roster[0] with { Level = 2 };
        run.SyncActivePartyProjection();
        var hireling = WithersHirelingCatalog.Matching("Zenith Feur'sel")!;

        var result = PartyPlanningRules.AddHireling(run, hireling);

        Assert.True(result.Applied);
        var added = Assert.Single(run.Roster!, member => member.IsHireling == true);
        Assert.Equal("hireling-zenith-feur-sel", added.Id);
        Assert.Equal(3, added.Level);
        Assert.Equal(RosterStatus.Camp, added.RosterStatus);
        Assert.Equal("Cleric", added.ClassName);
        Assert.False(PartyPlanningRules.AddHireling(run, hireling).Applied);
    }

    [Fact]
    public void HirelingLimitIsThreeAndActiveHirelingCannotBeRemoved()
    {
        var run = new HonorRun();
        var hires = WithersHirelingCatalog.All.Take(4).ToList();
        Assert.True(PartyPlanningRules.AddHireling(run, hires[0]).Applied);
        Assert.True(PartyPlanningRules.AddHireling(run, hires[1]).Applied);
        Assert.True(PartyPlanningRules.AddHireling(run, hires[2]).Applied);
        var fourth = PartyPlanningRules.AddHireling(run, hires[3]);
        Assert.False(fourth.Applied);
        Assert.Equal("Withers allows up to three hirelings in a run.", fourth.Error);

        var roster = run.Roster!;
        var member = roster.Single(candidate => candidate.Name == hires[0].Name);
        roster[roster.IndexOf(member)] = member with { Status = RosterStatus.Active };
        Assert.False(PartyPlanningRules.RemoveHireling(run, member.Id).Applied);
        roster[roster.FindIndex(candidate => candidate.Id == member.Id)] =
            member with { Status = RosterStatus.Camp };
        Assert.True(PartyPlanningRules.RemoveHireling(run, member.Id).Applied);
    }

    [Fact]
    public void RespecRestoresOracleDefaultsAndClearsRunSpecificPlanning()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        var index = run.Roster!.FindIndex(member => member.Name == "Shadowheart");
        var member = run.Roster[index] with
        {
            BuildId = "build",
            ClassName = "Fighter",
            PreparedTags = ["silence"],
            RoleOverride = "Tank",
            AbilityScores = AbilityScores.CustomDefault,
            AbilityModifiers =
            [
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Temporary,
                    AbilityModifierMode.Add,
                    2,
                    "Potion"),
            ],
            UsesBuildAbilityScores = true,
            AppliedAbilitySetupId = "setup",
            SourceLoadoutId = "source",
            ManualBuild = ManualBuildPlan.Empty("Manual", AbilityScores.CustomDefault),
        };
        run.Roster[index] = member;
        run.EquippedByMember = new() { [member.Id] = ["item"] };
        run.BuildAssignedAt = new() { [member.Id] = DateTimeOffset.UtcNow };
        run.PlannedSlotOverrides = new()
        {
            [member.Id] = new() { ["Helmet#0"] = "item" },
        };
        run.GearAssignmentOverrides = new() { ["item"] = member.Id };

        Assert.True(PartyPlanningRules.Respec(run, member.Id));

        var reset = run.Roster.Single(candidate => candidate.Id == member.Id);
        Assert.Null(reset.BuildId);
        Assert.Equal("Cleric", reset.ClassName);
        Assert.Empty(reset.PreparedTags);
        Assert.Empty(reset.AbilityModifiers!);
        Assert.False(reset.UsesBuildAbilityScores);
        Assert.Null(reset.ManualBuild);
        Assert.False(run.EquippedByMember.ContainsKey(member.Id));
        Assert.DoesNotContain(member.Id, run.GearAssignmentOverrides.Values);
    }

    [Fact]
    public void SwapPreservesRosterPositionsWhileExchangingActiveStatus()
    {
        var run = new HonorRun();
        run.NormalizeRoster();
        var roster = run.Roster!;
        var active = roster.First(member => member.RosterStatus == RosterStatus.Active);
        var camp = roster.First(member => member.RosterStatus == RosterStatus.Camp);
        var outgoingIndex = roster.IndexOf(active);
        var incomingIndex = roster.IndexOf(camp);

        var result = PartyPlanningRules.SwapIntoActive(run, camp.Id, active.Id);

        Assert.True(result.Applied);
        Assert.Equal(camp.Id, roster[outgoingIndex].Id);
        Assert.Equal(RosterStatus.Active, roster[outgoingIndex].RosterStatus);
        Assert.Equal(active.Id, roster[incomingIndex].Id);
        Assert.Equal(RosterStatus.Camp, roster[incomingIndex].RosterStatus);
    }

    [Fact]
    public void AssignBuildStampsRecencyAndKeepsOnlyPermanentCharacterRewards()
    {
        var build = Build(
            "cleric",
            "Cleric",
            Gear("Luminous Armour", "Chest", "Core"));
        var run = new HonorRun();
        run.NormalizeRoster();
        var member = run.Roster![0] with
        {
            AbilityModifiers =
            [
                new AbilityModifier(
                    Ability.Wisdom,
                    AbilityModifierKind.Permanent,
                    AbilityModifierMode.Add,
                    1,
                    "Mirror"),
                new AbilityModifier(
                    Ability.Strength,
                    AbilityModifierKind.Equipment,
                    AbilityModifierMode.Minimum,
                    19,
                    "Club"),
            ],
            AppliedAbilitySetupId = "old",
            ManualBuild = ManualBuildPlan.Empty("Old", AbilityScores.CustomDefault),
        };
        run.Roster[0] = member;
        run.PlannedSlotOverrides = new()
        {
            [member.Id] = new() { ["Helmet#0"] = "helmet" },
        };
        var stamp = DateTimeOffset.FromUnixTimeSeconds(123);

        Assert.True(
            PartyPlanningRules.AssignBuild(
                run,
                member.Id,
                build.Id,
                [build],
                stamp));

        var updated = run.Roster.Single(candidate => candidate.Id == member.Id);
        Assert.Equal(build.Id, updated.BuildId);
        Assert.Equal("Cleric", updated.ClassName);
        Assert.True(updated.UsesBuildAbilityScores);
        Assert.Null(updated.AppliedAbilitySetupId);
        Assert.Null(updated.ManualBuild);
        Assert.Single(updated.AbilityModifiers!);
        Assert.Equal(AbilityModifierKind.Permanent, updated.AbilityModifiers![0].Kind);
        Assert.Equal(stamp, run.BuildAssignedAt![member.Id]);
        Assert.False(run.PlannedSlotOverrides.ContainsKey(member.Id));
    }

    [Fact]
    public void WantedGearAppliesNonRingAndIndependentRingOverrides()
    {
        var build = Build(
            "fighter",
            "Fighter",
            Gear("Old Helm", "Head", "Core"),
            Gear("Ring One", "Ring", "Core"),
            Gear("Ring Two", "Ring", "Upgrade"));
        var run = new HonorRun();
        run.NormalizeRoster();
        var member = run.Roster![0] with { BuildId = build.Id, Level = 5 };
        run.Roster[0] = member;
        run.SyncActivePartyProjection();
        var catalog = new[]
        {
            Item("new-helm", "New Helm", "Head"),
            Item("new-ring", "New Ring", "Ring"),
        };

        PartyPlanningRules.SetSlotOverride(
            run,
            member,
            new DollCell(LoadoutSlot.Helmet),
            "new-helm",
            catalog);
        PartyPlanningRules.SetSlotOverride(
            run,
            member,
            new DollCell(LoadoutSlot.Rings, 1),
            "new-ring",
            catalog);
        var wanted = PartyPlanningRules.WantedGear(run, member, 1, [build], catalog);

        Assert.DoesNotContain(wanted, gear => gear.Item == "Old Helm");
        Assert.Contains(wanted, gear => gear.Item == "New Helm");
        Assert.Contains(wanted, gear => gear.Item == "Ring One");
        Assert.DoesNotContain(wanted, gear => gear.Item == "Ring Two");
        Assert.Contains(wanted, gear => gear.Item == "New Ring");
        Assert.Equal(
            "new-ring",
            PartyPlanningRules.SlotOverride(
                run,
                member,
                new DollCell(LoadoutSlot.Rings, 1),
                catalog));
    }

    [Fact]
    public void ConflictAndRoutePickupsUseDeterministicPlannedOwner()
    {
        var shared = Gear("Caustic Band", "Ring", "Core") with
        {
            Alternative = "Crusher's Ring",
        };
        var buildA = Build("a", "Alpha", shared);
        var buildB = Build("b", "Beta", shared);
        var run = new HonorRun();
        run.NormalizeRoster();
        var first = run.Roster![0] with { BuildId = buildA.Id };
        var second = run.Roster[1] with { BuildId = buildB.Id };
        run.Roster[0] = first;
        run.Roster[1] = second;
        run.SyncActivePartyProjection();
        run.BuildAssignedAt = new()
        {
            [first.Id] = DateTimeOffset.FromUnixTimeSeconds(1),
            [second.Id] = DateTimeOffset.FromUnixTimeSeconds(2),
        };

        var firstConflict = PartyPlanningRules.Conflict(
            run,
            shared,
            first,
            [buildA, buildB],
            []);
        var secondConflict = PartyPlanningRules.Conflict(
            run,
            shared,
            second,
            [buildA, buildB],
            []);
        var pickups = PartyPlanningRules.RoutePickups(run, [buildA, buildB], []);

        Assert.True(firstConflict?.Mine);
        Assert.False(secondConflict?.Mine);
        Assert.Contains("Alternative: Crusher's Ring", secondConflict?.Detail);
        var pickup = Assert.Single(pickups, item => item.Gear.ItemKey == shared.ItemKey);
        Assert.Equal(first.Id, pickup.MemberId);
    }

    [Fact]
    public void DollCellsMatchMacLabelsAndSplitRingPicks()
    {
        Assert.Equal(6, DollCell.PaperDollRows.Count);
        Assert.Equal("Shield / 2nd Sword", LoadoutSlot.OffHand.Label());
        Assert.Equal("Ring 2: no pick", new DollCell(LoadoutSlot.Rings, 1).EmptyLabel);
        var ringOne = Gear("Ring One", "Ring", "Core");
        var ringTwo = Gear("Ring Two", "Ring", "Upgrade");
        var grouped = new Dictionary<LoadoutSlot, IReadOnlyList<BuildGear>>
        {
            [LoadoutSlot.Rings] = [ringOne, ringTwo],
        };
        Assert.Equal(
            [ringOne],
            new DollCell(LoadoutSlot.Rings, 0).Items(grouped));
        Assert.Equal(
            [ringTwo],
            new DollCell(LoadoutSlot.Rings, 1).Items(grouped));
    }

    private static BuildSummary Build(
        string id,
        string name,
        params BuildGear[] gear) =>
        new()
        {
            Id = id,
            Name = name,
            Levels =
            [
                new BuildLevel(1, name, string.Empty, string.Empty, string.Empty, "Reviewed"),
            ],
            Gear = gear,
        };

    private static BuildGear Gear(string item, string slot, string priority) =>
        new()
        {
            Item = item,
            Slot = slot,
            Priority = priority,
            Act = 1,
            Region = "Druid Grove",
            Acquisition = "Fixture acquisition",
            Why = "Fixture why",
            Source = "Fixture",
        };

    private static ItemSummary Item(string key, string name, string slot) =>
        new()
        {
            ItemKey = key,
            Name = name,
            Slot = slot,
            Act = 1,
            Region = "Druid Grove",
            Acquisition = "Fixture acquisition",
        };
}
