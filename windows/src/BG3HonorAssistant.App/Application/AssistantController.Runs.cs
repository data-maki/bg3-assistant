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

        var active = await runRepository.LoadRecoverableActiveAsync(
            SnapshotIsValid,
            cancellationToken);
        if (active is null)
        {
            Run = CreateDefaultRun("Honor Run");
            await SaveAsync(cancellationToken);
        }
        else
        {
            Run = DeserializeRun(active.SnapshotJson);
            Run.NormalizeRoster();
            var runRecoveryNotice = string.Equals(
                active.SnapshotJson,
                (await runRepository.LoadActiveAsync(cancellationToken))?.SnapshotJson,
                StringComparison.Ordinal)
                ? null
                : "Recovered the newest valid run revision after an unreadable snapshot.";
            RecoveryNotice ??= runRecoveryNotice;
        }

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
        var saved = await runRepository.LoadAsync(id, cancellationToken);
        if (saved is null || !SnapshotIsValid(saved.SnapshotJson))
        {
            return false;
        }

        if (!await runRepository.SetActiveAsync(id, cancellationToken))
        {
            return false;
        }

        Run = DeserializeRun(saved.SnapshotJson);
        Run.NormalizeRoster();
        await RefreshRunsAsync(cancellationToken);
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
        var snapshot = JsonSerializer.Serialize(Run, json);
        await runRepository.SaveAsync(
            Run.Id,
            Run.Name ?? "Honor Run",
            Run.GuideVersion,
            snapshot,
            makeActive: true,
            cancellationToken);
        await RefreshRunsAsync(cancellationToken);
    }

    public async Task UpdatePreferencesAsync(
        AppPreferences preferences,
        CancellationToken cancellationToken = default)
    {
        Preferences = preferences;
        await runRepository.SetSettingAsync(
            PreferencesKey,
            JsonSerializer.Serialize(preferences, json),
            cancellationToken);
        Notify();
    }
}
