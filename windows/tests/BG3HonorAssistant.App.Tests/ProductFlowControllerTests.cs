using System.IO;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App.Tests;

public sealed class ProductFlowControllerTests : IDisposable
{
    private readonly string temporaryDirectory = Path.Combine(
        Path.GetTempPath(),
        "BG3HonorAssistant.ProductFlow.Tests",
        Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task PartyLevelBatchLeavesCampAndUnrecruitedPlansUntouched()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var inactiveLevels = controller.Run.Roster!
            .Where(member => member.RosterStatus != RosterStatus.Active)
            .ToDictionary(member => member.Id, member => member.Level);

        await controller.SetAllPartyLevelsAsync(7);

        Assert.All(controller.ActiveParty, member => Assert.Equal(7, member.Level));
        Assert.All(
            controller.Run.Roster!.Where(
                member => member.RosterStatus != RosterStatus.Active),
            member => Assert.Equal(inactiveLevels[member.Id], member.Level));
    }

    [Fact]
    public async Task FocusedExplorationHasNoFightGateAndDecisionNeedsAnOutcome()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var exploration = controller.Walkthrough.First(
            step => step.CheckpointId is null);

        await controller.FocusStepAsync(exploration);

        Assert.Same(exploration, controller.CurrentStep);
        Assert.Null(controller.CurrentCheckpoint);
        Assert.Null(controller.Readiness);

        var decision = controller.Walkthrough.First(step => step.Decision is not null);
        await controller.FocusStepAsync(decision);

        Assert.False(await controller.CompleteCurrentGoalAsync());
        Assert.Equal(
            CheckpointDisposition.Pending,
            RunSafety.WalkthroughDisposition(
                decision,
                controller.Run.WalkthroughProgress ??
                new Dictionary<string, CheckpointDisposition>()));

        Assert.True(
            await controller.ResolveOutcomeAsync(
                decision,
                decision.Decision!.Recommended.Label));
        Assert.Equal(
            decision.Decision.Recommended.Label,
            controller.Run.WalkthroughOutcomes?[decision.Id]);
    }

    [Fact]
    public async Task ManualBuildFlowRecordsClassFeatAndConditionalChoice()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var memberId = controller.ActiveParty[0].Id;

        Assert.True(await controller.BeginManualBuildAsync(memberId));
        Assert.True(await controller.SetManualClassAsync(memberId, 4, "Wizard"));
        var wizard = ClassCatalog.Definition("Wizard")!;
        var feat = Assert.Single(
            wizard.Levels[4].Choices,
            group => group.Id == "feat-4");
        var allocation = Assert.Single(
            wizard.Levels[4].Choices,
            group => group.Id == "ability-improvement-4");

        Assert.False(
            await controller.ToggleManualChoiceAsync(
                memberId,
                4,
                allocation,
                "+2 Intelligence"));
        Assert.True(
            await controller.ToggleManualChoiceAsync(
                memberId,
                4,
                feat,
                "Ability Improvement"));
        Assert.True(
            await controller.ToggleManualChoiceAsync(
                memberId,
                4,
                allocation,
                "+2 Intelligence"));

        var plan = controller.Run.Roster!
            .Single(member => member.Id == memberId)
            .ManualBuild!;
        Assert.Equal(
            ["Ability Improvement"],
            plan.Levels[3].Selections[feat.Id]);
        Assert.Equal(
            ["+2 Intelligence"],
            plan.Levels[3].Selections[allocation.Id]);
    }

    [Fact]
    public async Task LoadoutFlowPersistsSlotSwapAndContestedOwner()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var members = controller.ActiveParty.Take(2).ToArray();
        var build = controller.Builds.First(
            candidate => candidate.Gear.Any(
                gear => gear.Act == 1 && gear.IsMapObjective));
        Assert.True(await controller.AssignBuildAsync(members[0].Id, build.Id));
        Assert.True(await controller.AssignBuildAsync(members[1].Id, build.Id));
        members = controller.ActiveParty
            .Where(member => members.Any(original => original.Id == member.Id))
            .ToArray();
        var gear = PartyPlanningRules.WantedGear(
                controller.Run,
                members[0],
                1,
                controller.Builds,
                controller.Guide.Items)
            .First(item => item.IsMapObjective);

        Assert.True(
            await controller.SetGearAssignmentOverrideAsync(
                gear,
                members[1].Id));
        Assert.Equal(
            members[1].Id,
            PartyPlanningRules.PlannedOwnerId(
                controller.Run,
                gear.ItemKey,
                controller.Builds,
                controller.Guide.Items));

        var slot = LoadoutSlotClassifier.Classify(gear.Slot, gear.Item);
        var replacement = controller.Guide.Items.First(
            item =>
                item.Act <= 1 &&
                item.ItemKey != gear.ItemKey &&
                LoadoutSlotClassifier.Classify(item.Slot, item.Name) == slot);
        var cell = new DollCell(slot);

        Assert.True(
            await controller.SetSlotOverrideAsync(
                members[0].Id,
                cell,
                replacement.ItemKey));
        Assert.Equal(
            replacement.ItemKey,
            PartyPlanningRules.SlotOverride(
                controller.Run,
                members[0],
                cell,
                controller.Guide.Items));
    }

    public void Dispose()
    {
        if (Directory.Exists(temporaryDirectory))
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }

        GC.SuppressFinalize(this);
    }

    private AssistantController CreateController() =>
        new(
            new RunRepository(Path.Combine(temporaryDirectory, "state.sqlite3")),
            new GuideRepository());

    private static string FindGuidePath()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "Resources",
                "Data",
                "guide-bundle.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException("Could not locate the shared guide bundle.");
    }
}
