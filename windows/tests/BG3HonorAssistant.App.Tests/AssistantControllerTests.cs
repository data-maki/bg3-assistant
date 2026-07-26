using System.IO;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App.Tests;

public sealed class AssistantControllerTests : IDisposable
{
    private readonly string temporaryDirectory = Path.Combine(
        Path.GetTempPath(),
        "BG3HonorAssistant.App.Tests",
        Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task FirstStartCreatesNormalizedRecoverableRunFromSharedGuide()
    {
        var controller = CreateController();

        await controller.InitializeAsync(FindGuidePath());

        Assert.Equal(controller.Guide.GuideVersion, controller.Run.GuideVersion);
        Assert.Equal(12, controller.Run.Roster?.Count);
        Assert.Equal(4, controller.ActiveParty.Count);
        Assert.Equal(1, controller.Run.SelectedAct);
        Assert.NotNull(controller.CurrentStep);
        Assert.NotNull(controller.CurrentCheckpoint);
        Assert.Single(controller.Runs);
        Assert.True(controller.Runs[0].IsActive);
    }

    [Fact]
    public async Task RouteMutationSurvivesControllerAndRepositoryRestart()
    {
        var first = CreateController();
        await first.InitializeAsync(FindGuidePath());
        var step = first.CurrentStep!;
        var runId = first.Run.Id;

        Assert.True(
            await first.SetCurrentDispositionAsync(
                CheckpointDisposition.Completed));

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());

        Assert.Equal(runId, restarted.Run.Id);
        Assert.Equal(
            CheckpointDisposition.Completed,
            restarted.Run.WalkthroughProgress?[step.Id]);
        Assert.NotEqual(step.Id, restarted.CurrentStep?.Id);
    }

    [Fact]
    public async Task RunCreationAndSwitchingPreserveIndependentSnapshots()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var firstId = controller.Run.Id;
        await controller.RenameRunAsync("First");
        await controller.CreateRunAsync(
            "Second",
            RunDifficulty.Tactician,
            RouteRevealPolicy.NextThree);
        var secondId = controller.Run.Id;

        Assert.NotEqual(firstId, secondId);
        Assert.Equal(2, controller.Runs.Count);
        Assert.True(await controller.SwitchRunAsync(firstId));
        Assert.Equal("First", controller.Run.Name);
        Assert.Equal(firstId, controller.Run.Id);
        Assert.True(await controller.SwitchRunAsync(secondId));
        Assert.Equal(RunDifficulty.Tactician, controller.Run.Difficulty);
        Assert.Equal(RouteRevealPolicy.NextThree, controller.Run.RouteRevealPolicy);
    }

    [Fact]
    public async Task PreferencesAndActTwoGapSurviveRestart()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        await controller.UpdatePreferencesAsync(
            new AppPreferences
            {
                OnboardingVersion = OnboardingFlow.Version,
                OverlayDensity = OverlayDensity.Reference,
                ShowOverlayWhileGameRuns = false,
                ReducedMotion = true,
                OverlayAnchorX = 0.25,
                OverlayAnchorY = 0.75,
            });
        controller.Run.SelectedAct = 2;
        await controller.SaveAsync();

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());

        Assert.Equal(OverlayDensity.Reference, restarted.Preferences.OverlayDensity);
        Assert.False(restarted.Preferences.ShowOverlayWhileGameRuns);
        Assert.True(restarted.Preferences.ReducedMotion);
        Assert.Equal(0.25, restarted.Preferences.OverlayAnchorX);
        Assert.Equal(0.75, restarted.Preferences.OverlayAnchorY);
        Assert.False(restarted.Payload.RouteAvailable);
        Assert.Equal(
            "Act 2 route is not available in this guide version",
            restarted.GoalPresentation.Avoid);
    }

    [Fact]
    public async Task GearTargetReplacesNowGoalAndCompletionRecordsOwnership()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var member = controller.ActiveParty[0];
        var build = controller.Builds.First(candidate =>
            candidate.Gear.Any(gear => gear.Act == 1 && gear.IsMapObjective));
        Assert.True(await controller.AssignBuildAsync(member.Id, build.Id));
        member = controller.ActiveParty.Single(candidate => candidate.Id == member.Id);
        var gear = PartyPlanningRules.WantedGear(
                controller.Run,
                member,
                1,
                controller.Builds,
                controller.Guide.Items)
            .First(candidate => candidate.IsMapObjective);

        Assert.True(await controller.SetGearTargetAsync(member.Id, gear));
        Assert.IsType<BG3HonorAssistant.Core.Route.CurrentGoal.GearTargetGoal>(
            controller.CurrentGoal);
        Assert.Equal($"Get {gear.Item}", controller.GoalPresentation.Title);

        Assert.True(await controller.CompleteCurrentGoalAsync());
        Assert.Null(controller.Run.GearTarget);
        Assert.Equal(member.Id, controller.Run.EquipmentOwnerId(gear.ItemKey));
    }

    [Fact]
    public async Task FightPinSnoozeAndMuteRemainExplicitSessionAndRunState()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());

        Assert.True(controller.PinCurrentFight());
        Assert.True(controller.CombatCardPinned);
        Assert.Equal(3, controller.CombatPinLines.Count);
        controller.SnoozeWarnings();
        Assert.True(controller.WarningsSuppressed);
        controller.UnpinFight();
        Assert.False(controller.CombatCardPinned);

        await controller.ToggleMuteCurrentAsync();
        Assert.True(controller.WarningsSuppressed);
        var muted = controller.CurrentCheckpoint!.Id;

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());
        Assert.Contains(muted, restarted.Run.MutedCheckpointIds!);
        Assert.False(restarted.CombatCardPinned);
        Assert.Null(restarted.SnoozedUntil);
    }

    [Fact]
    public async Task ActAdvanceRequiresConsequenceConsentAndActTwoCannotInventAGate()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());

        Assert.Null(controller.ActTransitionBlockedReason);
        Assert.NotEmpty(controller.CurrentActConsequences);
        var consequenceCount = controller.CurrentActConsequences.Count;
        Assert.False(await controller.AdvanceActAsync(acceptingRouteConsequences: false));
        Assert.True(await controller.AdvanceActAsync(acceptingRouteConsequences: true));
        Assert.Equal(2, controller.Run.SelectedAct);
        Assert.True(controller.Run.ActLedgerIsLocked(1));
        Assert.Single(controller.Run.ActTransitions!);
        Assert.Equal(
            consequenceCount,
            controller.Run.ActTransitions![0].UnresolvedRouteCount);
        Assert.Equal(
            "Act 2 route coverage must be reviewed before this gate can unlock.",
            controller.ActTransitionBlockedReason);
        Assert.False(await controller.AdvanceActAsync(acceptingRouteConsequences: true));
        Assert.Equal(
            "Act 2 route is not available in this guide version",
            controller.GoalPresentation.Avoid);
    }

    [Fact]
    public async Task ImportedBuildPersistsGloballyAndCanBeAssigned()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var template = controller.Builds[0];
        var imported = new ImportedBuild(
            "imported-controller-test",
            "Imported Controller Test",
            "https://example.com/build",
            template with
            {
                Id = "imported-controller-test",
                Name = "Imported Controller Test",
                HonorStatus = "Imported; verify choices in game",
            });

        await controller.SaveImportedBuildAsync(imported);
        Assert.Contains(
            controller.Builds,
            build => build.Id == imported.Id);
        Assert.True(
            await controller.AssignBuildAsync(
                controller.ActiveParty[0].Id,
                imported.Id));

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());

        Assert.Contains(
            restarted.ImportedBuilds,
            build => build.Id == imported.Id);
        Assert.Equal(imported.Id, restarted.ActiveParty[0].BuildId);
        Assert.False(await restarted.DeleteImportedBuildAsync(imported.Id));
        Assert.True(
            await restarted.AssignBuildAsync(
                restarted.ActiveParty[0].Id,
                buildId: null));
        Assert.True(await restarted.DeleteImportedBuildAsync(imported.Id));
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
                "mac",
                "BG3Assistant",
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
