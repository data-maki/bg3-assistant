using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    private readonly object persistenceSync = new();
    private Task persistenceTail = Task.CompletedTask;
    private Task runTransitionTail = Task.CompletedTask;
    private readonly List<Exception> persistenceFailures = [];
    private bool persistenceSealed;

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

    private bool SnapshotMatchesRow(SavedRun row, string snapshot)
    {
        try
        {
            var run = DeserializeRun(snapshot);
            return string.Equals(run.Id, row.Id, StringComparison.Ordinal) &&
                   string.Equals(
                       run.Name ?? "Honor Run",
                       row.Name,
                       StringComparison.Ordinal) &&
                   string.Equals(
                       run.GuideVersion,
                       row.GuideVersion,
                       StringComparison.Ordinal);
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

    public async Task FlushAsync(CancellationToken cancellationToken = default)
    {
        await FlushPersistenceAsync(seal: false, cancellationToken).ConfigureAwait(false);
    }

    public async Task SealAndFlushAsync(CancellationToken cancellationToken = default)
    {
        Task transitions;
        lock (persistenceSync)
        {
            persistenceSealed = true;
            transitions = runTransitionTail;
        }

        await transitions.WaitAsync(cancellationToken).ConfigureAwait(false);
        await FlushPersistenceAsync(seal: false, cancellationToken).ConfigureAwait(false);
    }

    private async Task FlushPersistenceAsync(
        bool seal,
        CancellationToken cancellationToken)
    {
        while (true)
        {
            Task pending;
            lock (persistenceSync)
            {
                if (seal)
                {
                    persistenceSealed = true;
                }

                pending = persistenceTail;
            }

            await pending.WaitAsync(cancellationToken).ConfigureAwait(false);
            lock (persistenceSync)
            {
                if (ReferenceEquals(pending, persistenceTail))
                {
                    if (persistenceFailures.Count > 0)
                    {
                        throw new AggregateException(
                            "One or more durable state writes failed.",
                            persistenceFailures);
                    }

                    return;
                }
            }
        }
    }

    private Task EnqueuePersistenceAsync(
        Func<CancellationToken, Task> operation,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(operation);
        return EnqueuePersistenceAsync(
            async token =>
            {
                await operation(token).ConfigureAwait(false);
                return true;
            },
            cancellationToken);
    }

    private Task<T> EnqueuePersistenceAsync<T>(
        Func<CancellationToken, Task<T>> operation,
        CancellationToken cancellationToken,
        bool allowWhenSealed = false)
    {
        ArgumentNullException.ThrowIfNull(operation);
        Task predecessor;
        TaskCompletionSource completion;
        lock (persistenceSync)
        {
            if (persistenceSealed && !allowWhenSealed)
            {
                return Task.FromException<T>(
                    new InvalidOperationException(
                        "Durable state is sealed because the application is exiting."));
            }

            predecessor = persistenceTail;
            completion = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            persistenceTail = completion.Task;
        }

        return ExecuteQueuedPersistenceAsync(
            predecessor,
            completion,
            operation,
            cancellationToken);
    }

    private async Task<T> ExecuteQueuedPersistenceAsync<T>(
        Task predecessor,
        TaskCompletionSource completion,
        Func<CancellationToken, Task<T>> operation,
        CancellationToken cancellationToken)
    {
        try
        {
            await predecessor.ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            return await operation(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            lock (persistenceSync)
            {
                persistenceFailures.Add(exception);
            }

            throw;
        }
        finally
        {
            completion.TrySetResult();
        }
    }

    private void AddRecoveryNotice(string notice)
    {
        RecoveryNotice = string.IsNullOrWhiteSpace(RecoveryNotice)
            ? notice
            : $"{RecoveryNotice} {notice}";
    }

    private async Task<TResult> RunSerializedTransitionAsync<TResult>(
        Func<Task<TResult>> transition)
    {
        ArgumentNullException.ThrowIfNull(transition);
        Task predecessor;
        TaskCompletionSource completion;
        lock (persistenceSync)
        {
            if (persistenceSealed)
            {
                throw new InvalidOperationException(
                    "Durable state is sealed because the application is exiting.");
            }

            predecessor = runTransitionTail;
            completion = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            runTransitionTail = completion.Task;
        }

        try
        {
            await predecessor.ConfigureAwait(false);
            return await transition().ConfigureAwait(false);
        }
        finally
        {
            completion.TrySetResult();
        }
    }

    private Task CurrentRunTransition()
    {
        lock (persistenceSync)
        {
            return runTransitionTail;
        }
    }

    private static readonly IReadOnlyDictionary<string, CheckpointDisposition> EmptyProgress =
        new Dictionary<string, CheckpointDisposition>();

    private static readonly IReadOnlyDictionary<string, string> EmptyOutcomes =
        new Dictionary<string, string>();
}
