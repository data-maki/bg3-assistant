namespace BG3HonorAssistant.Infrastructure.Persistence;

public sealed record SavedRun(
    string Id,
    string Name,
    string GuideVersion,
    string SnapshotJson,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    bool IsActive);
