namespace BG3HonorAssistant.Infrastructure.Persistence;

public sealed record SavedRun(
    string Id,
    string Name,
    string GuideVersion,
    string SnapshotJson,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    bool IsActive);

public sealed record RecoverableRunResult(
    SavedRun? Run,
    bool HadActiveRun,
    bool UsedRevision,
    string? UnreadableActiveSnapshot = null);
