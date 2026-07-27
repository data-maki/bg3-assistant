using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    public async Task InitializeAsync(
        string guidePath,
        CancellationToken cancellationToken = default)
    {
        Guide = await guideRepository.LoadAsync(guidePath, cancellationToken);
        await runRepository.InitializeAsync(cancellationToken);
        Preferences = await LoadPreferencesAsync(cancellationToken);
        await RefreshImportedBuildsAsync(cancellationToken);

        var recovery = await runRepository.LoadRecoverableActiveWithStatusAsync(
            SnapshotMatchesRow,
            cancellationToken);
        if (recovery.Run is null)
        {
            Run = CreateDefaultRun("Honor Run");
            if (recovery.HadActiveRun)
            {
                AddRecoveryNotice(
                    "The active run and all retained revisions were unreadable. " +
                    "A new run was created while the prior database rows were preserved.");
            }

            await SaveAsync(cancellationToken);
        }
        else
        {
            var active = recovery.Run;
            Run = DeserializeRun(active.SnapshotJson);
            Run.NormalizeRoster();
            if (recovery.UsedRevision)
            {
                await runRepository.SaveRecoveryEvidenceAsync(
                    active.Id,
                    recovery.UnreadableActiveSnapshot ??
                    throw new InvalidOperationException(
                        "Recovery did not retain the rejected active snapshot."),
                    "Active snapshot failed validation during startup recovery.",
                    cancellationToken);
                AddRecoveryNotice(
                    "Recovered the newest valid run revision after an unreadable snapshot " +
                    "and repaired the active snapshot.");
                await SaveAsync(cancellationToken);
            }
        }

        await EnsureGuideCompatibilityAsync(cancellationToken);

        await RefreshRunsAsync(cancellationToken);
        Notify();
    }

    public async Task CreateRunAsync(
        string name,
        RunDifficulty difficulty,
        RouteRevealPolicy revealPolicy,
        CancellationToken cancellationToken = default)
    {
        Run = CreateDefaultRun(string.IsNullOrWhiteSpace(name) ? "Honor Run" : name.Trim());
        CombatCardPinned = false;
        Run.Difficulty = difficulty;
        Run.RouteRevealPolicy = revealPolicy;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task CreateRunWithCurrentPartyPresetAsync(
        string name,
        RunDifficulty difficulty,
        RouteRevealPolicy revealPolicy,
        CancellationToken cancellationToken = default)
    {
        Run = Run.FreshRun(
            string.IsNullOrWhiteSpace(name) ? "Honor Run" : name.Trim(),
            Guide.GuideVersion,
            Builds,
            DateTimeOffset.UtcNow);
        CombatCardPinned = false;
        Run.Difficulty = difficulty;
        Run.RouteRevealPolicy = revealPolicy;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task UpdateRunSettingsAsync(
        RunDifficulty difficulty,
        RouteRevealPolicy revealPolicy,
        CancellationToken cancellationToken = default)
    {
        Run.Difficulty = difficulty;
        Run.RouteRevealPolicy = revealPolicy;
        await SaveAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> SwitchRunAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        var switched = await RunSerializedTransitionAsync(
            () => EnqueuePersistenceAsync(
                async token =>
                {
                    var candidate = await runRepository.LoadAsync(
                        id,
                        token).ConfigureAwait(false);
                    if (candidate is null ||
                        !SnapshotMatchesRow(candidate, candidate.SnapshotJson) ||
                        !await runRepository.SetActiveAsync(id, token).ConfigureAwait(false))
                    {
                        return false;
                    }

                    Run = DeserializeRun(candidate.SnapshotJson);
                    Run.NormalizeRoster();
                    CombatCardPinned = false;
                    await EnsureGuideCompatibilityAsync(
                        token,
                        persistenceIsSerialized: true).ConfigureAwait(false);
                    await RefreshRunsAsync(token).ConfigureAwait(false);
                    return true;
                },
                cancellationToken,
                allowWhenSealed: true));
        if (!switched)
        {
            return false;
        }

        Notify();
        return true;
    }

    public async Task RenameRunAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        if (!string.IsNullOrWhiteSpace(name))
        {
            Run.Name = name.Trim();
            await SaveAsync(cancellationToken);
            Notify();
        }
    }

    public async Task SaveAsync(CancellationToken cancellationToken = default)
    {
        await CurrentRunTransition()
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        var snapshot = JsonSerializer.Serialize(Run, json);
        var id = Run.Id;
        var name = Run.Name ?? "Honor Run";
        var guideVersion = Run.GuideVersion;
        await EnqueuePersistenceAsync(
            async token =>
            {
                await runRepository.SaveAsync(
                    id,
                    name,
                    guideVersion,
                    snapshot,
                    makeActive: true,
                    token).ConfigureAwait(false);
                await RefreshRunsAsync(token).ConfigureAwait(false);
            },
            cancellationToken);
    }

    private async Task SaveCurrentRunCoreAsync(CancellationToken cancellationToken)
    {
        var snapshot = JsonSerializer.Serialize(Run, json);
        var id = Run.Id;
        var name = Run.Name ?? "Honor Run";
        var guideVersion = Run.GuideVersion;
        await runRepository.SaveAsync(
            id,
            name,
            guideVersion,
            snapshot,
            makeActive: true,
            cancellationToken).ConfigureAwait(false);
        await RefreshRunsAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task UpdatePreferencesAsync(
        AppPreferences preferences,
        CancellationToken cancellationToken = default)
    {
        Preferences = preferences;
        var value = JsonSerializer.Serialize(preferences, json);
        await EnqueuePersistenceAsync(
            token => runRepository.SetSettingAsync(
                PreferencesKey,
                value,
                token),
            cancellationToken);
        Notify();
    }

    private async Task EnsureGuideCompatibilityAsync(
        CancellationToken cancellationToken,
        bool persistenceIsSerialized = false)
    {
        if (string.IsNullOrWhiteSpace(Run.GuideVersion))
        {
            Run.GuideVersion = Guide.GuideVersion;
            if (persistenceIsSerialized)
            {
                await SaveCurrentRunCoreAsync(cancellationToken).ConfigureAwait(false);
            }
            else
            {
                await SaveAsync(cancellationToken);
            }

            return;
        }

        if (string.Equals(
                Run.GuideVersion,
                Guide.GuideVersion,
                StringComparison.Ordinal))
        {
            return;
        }

        var priorName = Run.Name ?? "Honor Run";
        var priorVersion = Run.GuideVersion;
        Run = Run.FreshRun(
            $"{priorName} (updated guide)",
            Guide.GuideVersion,
            Builds,
            DateTimeOffset.UtcNow);
        CombatCardPinned = false;
        if (persistenceIsSerialized)
        {
            await SaveCurrentRunCoreAsync(cancellationToken).ConfigureAwait(false);
        }
        else
        {
            await SaveAsync(cancellationToken);
        }

        AddRecoveryNotice(
            $"The saved run uses guide {priorVersion}. It remains available, and a " +
            $"compatible run was created for guide {Guide.GuideVersion}.");
    }
}
