namespace BG3HonorAssistant.Core.Models;

public sealed record RoutePayload
{
    public required int Act { get; init; }

    public required string GuideVersion { get; init; }

    public required bool RouteAvailable { get; init; }

    public IReadOnlyList<BuildSummary> Builds { get; init; } = [];

    public IReadOnlyList<RouteCheckpoint> Checkpoints { get; init; } = [];

    public IReadOnlyList<WalkthroughStep> Walkthrough { get; init; } = [];

    public IReadOnlyList<TimedEvent> TimedEvents { get; init; } = [];

    public IReadOnlyList<ActGuideSummary> Acts { get; init; } = [];
}

public sealed record GuideBundle
{
    public required string GuideVersion { get; init; }

    public IReadOnlyList<ItemSummary> Items { get; init; } = [];

    public required IReadOnlyDictionary<string, RoutePayload> Payloads { get; init; }
}
