using System.IO;
using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;
using Microsoft.Data.Sqlite;

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
    public async Task CreateAndSwitchClearFightPinButKeepSessionSnooze()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var firstId = controller.Run.Id;
        Assert.True(controller.PinCurrentFight());
        controller.SnoozeWarnings();
        var snoozedUntil = controller.SnoozedUntil;

        await controller.CreateRunAsync(
            "Second",
            RunDifficulty.Honour,
            RouteRevealPolicy.Everything);

        Assert.False(controller.CombatCardPinned);
        Assert.Equal(snoozedUntil, controller.SnoozedUntil);
        Assert.True(controller.PinCurrentFight());
        Assert.True(await controller.SwitchRunAsync(firstId));
        Assert.False(controller.CombatCardPinned);
        Assert.Equal(snoozedUntil, controller.SnoozedUntil);
    }

    [Fact]
    public async Task OrderedPersistenceFlushKeepsLastInvokedRunAndPreferenceWrites()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        var writes = new List<Task>();
        for (var index = 0; index < 32; index++)
        {
            controller.Run.Name = $"Run {index:D2}";
            writes.Add(controller.SaveAsync());
            writes.Add(
                controller.UpdatePreferencesAsync(
                    controller.Preferences with
                    {
                        OverlayAnchorX = index,
                    }));
        }

        await controller.FlushAsync();
        await Task.WhenAll(writes);

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());
        Assert.Equal("Run 31", restarted.Run.Name);
        Assert.Equal(31D, restarted.Preferences.OverlayAnchorX);
    }

    [Fact]
    public async Task SaveInvokedDuringSwitchCannotReactivatePreviousRun()
    {
        var repository = new RunRepository(
            Path.Combine(temporaryDirectory, "state.sqlite3"));
        var controller = new AssistantController(repository, new GuideRepository());
        await controller.InitializeAsync(FindGuidePath());
        var firstId = controller.Run.Id;
        await controller.CreateRunAsync(
            "Second",
            RunDifficulty.Honour,
            RouteRevealPolicy.Everything);

        var switchTask = controller.SwitchRunAsync(firstId);
        var saveTask = controller.SaveAsync();
        await Task.WhenAll(switchTask, saveTask);

        Assert.True(await switchTask);
        Assert.Equal(firstId, controller.Run.Id);
        Assert.Equal(firstId, (await repository.LoadActiveAsync())?.Id);
    }

    [Fact]
    public async Task FlushSurfacesFailedWritesAndSealRejectsNewProducers()
    {
        var controller = CreateController();
        await controller.InitializeAsync(FindGuidePath());
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => controller.UpdatePreferencesAsync(
                controller.Preferences with { OverlayAnchorX = 0.75D },
                cancellation.Token));
        await Assert.ThrowsAsync<AggregateException>(() => controller.FlushAsync());

        var clean = new AssistantController(
            new RunRepository(Path.Combine(temporaryDirectory, "sealed.sqlite3")),
            new GuideRepository());
        await clean.InitializeAsync(FindGuidePath());
        await clean.SealAndFlushAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(() => clean.SaveAsync());
    }

    [Fact]
    public async Task IncoherentRowAndPayloadIdentityAreNotActivated()
    {
        var repository = new RunRepository(
            Path.Combine(temporaryDirectory, "state.sqlite3"));
        var guide = await new GuideRepository().LoadAsync(FindGuidePath());
        var payload = new HonorRun
        {
            Name = "Payload",
            GuideVersion = guide.GuideVersion,
        };
        payload.NormalizeRoster();
        await repository.SaveAsync(
            "row-id",
            "Row",
            guide.GuideVersion,
            JsonSerializer.Serialize(payload, JsonDefaults.Create()));

        var controller = new AssistantController(repository, new GuideRepository());
        await controller.InitializeAsync(FindGuidePath());

        Assert.NotEqual("row-id", controller.Run.Id);
        Assert.NotEqual(payload.Id, controller.Run.Id);
        Assert.Contains(
            "all retained revisions were unreadable",
            controller.RecoveryNotice,
            StringComparison.Ordinal);
        var preserved = await repository.LoadAsync("row-id");
        Assert.NotNull(preserved);
        Assert.False(preserved.IsActive);
        Assert.False(await controller.SwitchRunAsync("row-id"));
    }

    [Fact]
    public async Task GuideUpgradePreservesPriorRunAndCreatesCompatibleActiveRun()
    {
        var databasePath = Path.Combine(temporaryDirectory, "state.sqlite3");
        var repository = new RunRepository(databasePath);
        var oldRun = new HonorRun
        {
            Name = "Legacy",
            GuideVersion = "old-guide",
        };
        oldRun.NormalizeRoster();
        oldRun.Roster![0] = oldRun.Roster[0] with { Level = 7 };
        oldRun.SyncActivePartyProjection();
        await repository.SaveAsync(
            oldRun.Id,
            oldRun.Name,
            oldRun.GuideVersion,
            JsonSerializer.Serialize(oldRun, JsonDefaults.Create()));

        var controller = new AssistantController(repository, new GuideRepository());
        await controller.InitializeAsync(FindGuidePath());

        Assert.NotEqual(oldRun.Id, controller.Run.Id);
        Assert.Equal(controller.Guide.GuideVersion, controller.Run.GuideVersion);
        Assert.Equal(1, controller.ActiveParty[0].Level);
        Assert.Contains("old-guide", controller.RecoveryNotice, StringComparison.Ordinal);
        var preserved = await repository.LoadAsync(oldRun.Id);
        Assert.NotNull(preserved);
        Assert.False(preserved.IsActive);
        Assert.Equal(2, controller.Runs.Count);
        Assert.Single(controller.Runs, run => run.IsActive);

        Assert.True(await controller.SwitchRunAsync(oldRun.Id));
        Assert.NotEqual(oldRun.Id, controller.Run.Id);
        Assert.Equal(controller.Guide.GuideVersion, controller.Run.GuideVersion);
        Assert.Equal(3, controller.Runs.Count);
    }

    [Fact]
    public async Task RecoveredRevisionRepairsActiveSnapshotOnlyOnce()
    {
        var first = CreateController();
        await first.InitializeAsync(FindGuidePath());
        var runId = first.Run.Id;
        await ReplaceActiveAndRevisionSnapshotsAsync(
            corruptActiveOnly: true);

        var recovered = CreateController();
        await recovered.InitializeAsync(FindGuidePath());
        Assert.Equal(runId, recovered.Run.Id);
        Assert.Contains("repaired", recovered.RecoveryNotice, StringComparison.Ordinal);
        var repository = new RunRepository(
            Path.Combine(temporaryDirectory, "state.sqlite3"));
        Assert.Equal(["{invalid"], await repository.ListRecoveryEvidenceAsync(runId));

        var restarted = CreateController();
        await restarted.InitializeAsync(FindGuidePath());
        Assert.Equal(runId, restarted.Run.Id);
        Assert.Null(restarted.RecoveryNotice);
    }

    [Fact]
    public async Task NoValidSnapshotCreatesExplicitlyNoticedFreshRunAndKeepsOldRow()
    {
        var first = CreateController();
        await first.InitializeAsync(FindGuidePath());
        var oldRunId = first.Run.Id;
        await ReplaceActiveAndRevisionSnapshotsAsync(
            corruptActiveOnly: false);

        var recovered = CreateController();
        await recovered.InitializeAsync(FindGuidePath());

        Assert.NotEqual(oldRunId, recovered.Run.Id);
        Assert.Contains("all retained revisions were unreadable", recovered.RecoveryNotice);
        Assert.Equal(2, recovered.Runs.Count);
        Assert.Contains(recovered.Runs, run => run.Id == oldRunId && !run.IsActive);
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
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "Resources",
            "Data",
            "guide-bundle.json");
        Assert.True(File.Exists(path), $"Bundled guide was not copied to {path}.");
        return path;
    }

    private async Task ReplaceActiveAndRevisionSnapshotsAsync(bool corruptActiveOnly)
    {
        var databasePath = Path.Combine(temporaryDirectory, "state.sqlite3");
        await using var connection = new SqliteConnection(
            new SqliteConnectionStringBuilder
            {
                DataSource = databasePath,
                Mode = SqliteOpenMode.ReadWrite,
                Pooling = false,
            }.ToString());
        await connection.OpenAsync();
        using var command = connection.CreateCommand();
        command.CommandText = corruptActiveOnly
            ? "UPDATE runs SET snapshot_json = '{invalid' WHERE is_active = 1;"
            : """
              UPDATE runs SET snapshot_json = '{invalid' WHERE is_active = 1;
              UPDATE run_revisions SET snapshot_json = '{invalid';
              """;
        await command.ExecuteNonQueryAsync();
    }
}
