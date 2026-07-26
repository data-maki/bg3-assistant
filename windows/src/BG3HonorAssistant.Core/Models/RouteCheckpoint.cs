using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public sealed record RouteCheckpoint
{
    public required string Id { get; init; }

    [JsonPropertyName("route_order")]
    public required int RouteOrder { get; init; }

    public required string Name { get; init; }

    public required string Area { get; init; }

    public required string Region { get; init; }

    public int? X { get; init; }

    public int? Y { get; init; }

    [JsonPropertyName("minimum_level")]
    public required int MinimumLevel { get; init; }

    public required string Importance { get; init; }

    public required string Danger { get; init; }

    public string Enemies { get; init; } = string.Empty;

    public string Advice { get; init; } = string.Empty;

    [JsonPropertyName("legendary_action")]
    public string? LegendaryAction { get; init; }

    [JsonPropertyName("failure_conditions")]
    public IReadOnlyList<string> FailureConditions { get; init; } = [];

    public IReadOnlyList<string> Preparation { get; init; } = [];

    [JsonPropertyName("completion_checks")]
    public IReadOnlyList<string> CompletionChecks { get; init; } = [];

    [JsonPropertyName("irreversible_warnings")]
    public IReadOnlyList<string> IrreversibleWarnings { get; init; } = [];

    public IReadOnlyList<string> Prerequisites { get; init; } = [];

    public IReadOnlyList<string> Notes { get; init; } = [];

    [JsonPropertyName("honor_decisions")]
    public IReadOnlyList<HonorDecision> HonorDecisions { get; init; } = [];

    public GuideSource Source { get; init; } = new(string.Empty, null, string.Empty);
}
