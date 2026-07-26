using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    private HonorRun CreateDefaultRun(string name)
    {
        var run = new HonorRun
        {
            Name = name,
            CreatedAt = DateTimeOffset.UtcNow,
            GuideVersion = Guide.GuideVersion,
        };
        run.NormalizeRoster();
        return run;
    }

    private async Task<AppPreferences> LoadPreferencesAsync(
        CancellationToken cancellationToken)
    {
        var value = await runRepository.GetSettingAsync(
            PreferencesKey,
            cancellationToken);
        if (value is null)
        {
            return new AppPreferences();
        }

        try
        {
            return JsonSerializer.Deserialize<AppPreferences>(value, json) ?? new();
        }
        catch (JsonException)
        {
            return new AppPreferences();
        }
    }

    private async Task RefreshRunsAsync(CancellationToken cancellationToken)
    {
        Runs = await runRepository.ListAsync(cancellationToken);
    }

    private async Task RefreshImportedBuildsAsync(CancellationToken cancellationToken)
    {
        importedBuilds.Clear();
        foreach (var value in await runRepository.ListImportedBuildJsonAsync(cancellationToken))
        {
            try
            {
                if (JsonSerializer.Deserialize<ImportedBuild>(value, json) is { } imported)
                {
                    importedBuilds.Add(imported);
                }
            }
            catch (JsonException)
            {
                RecoveryNotice ??=
                    "One saved imported build was unreadable and was not loaded.";
            }
        }
    }

    private bool SnapshotIsValid(string snapshot)
    {
        try
        {
            _ = DeserializeRun(snapshot);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private HonorRun DeserializeRun(string snapshot) =>
        JsonSerializer.Deserialize<HonorRun>(snapshot, json) ??
        throw new JsonException("Run snapshot decoded to null.");

    private IReadOnlyDictionary<string, CheckpointDisposition> CheckpointDispositions()
    {
        var result = new Dictionary<string, CheckpointDisposition>(StringComparer.Ordinal);
        foreach (var step in Walkthrough.Where(step => step.CheckpointId is not null))
        {
            result[step.CheckpointId!] = RunSafety.WalkthroughDisposition(
                step,
                Run.WalkthroughProgress ?? EmptyProgress);
        }

        return result;
    }

    private IReadOnlySet<string> CompletedCheckpointIds() =>
        CheckpointDispositions()
            .Where(pair => pair.Value.CountsAsCompleted())
            .Select(pair => pair.Key)
            .ToHashSet(StringComparer.Ordinal);

    private void SyncRegion()
    {
        if (RunSafety.NextWalkthroughStep(
                Walkthrough,
                Run.WalkthroughProgress ?? EmptyProgress,
                Run.WalkthroughOutcomes,
                LowestPartyLevel) is { } next)
        {
            Run.MapRegion = next.Region;
        }
    }

    private void Notify() => StateChanged?.Invoke(this, EventArgs.Empty);

    private static readonly IReadOnlyDictionary<string, CheckpointDisposition> EmptyProgress =
        new Dictionary<string, CheckpointDisposition>();

    private static readonly IReadOnlyDictionary<string, string> EmptyOutcomes =
        new Dictionary<string, string>();
}
