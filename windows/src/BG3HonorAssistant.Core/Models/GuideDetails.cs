using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public sealed record HonorDecision(string Text, string Kind);

public sealed record DecisionOption(
    string Label,
    IReadOnlyList<string> Benefits,
    IReadOnlyList<string> Costs);

public sealed record WalkthroughDecision(
    string Prompt,
    DecisionOption Recommended,
    IReadOnlyList<DecisionOption> Alternatives,
    bool Reversible,
    string Authority);

public sealed record IncidentProtocol
{
    public required string Trigger { get; init; }

    [JsonPropertyName("safe_actions")]
    public IReadOnlyList<string> SafeActions { get; init; } = [];

    public required string Never { get; init; }

    public required string Escape { get; init; }

    [JsonPropertyName("honor_delta")]
    public required string HonorDelta { get; init; }

    [JsonPropertyName("post_fight")]
    public IReadOnlyList<string> PostFight { get; init; } = [];

    public required string Authority { get; init; }

    [JsonPropertyName("source_url")]
    public required string SourceUrl { get; init; }
}

public sealed record RiskReward
{
    public required string Reward { get; init; }

    public required string Risk { get; init; }

    [JsonPropertyName("skip_cost")]
    public required string SkipCost { get; init; }

    [JsonPropertyName("return_by")]
    public required string ReturnBy { get; init; }
}

public sealed record ItemSummary
{
    [JsonPropertyName("item_key")]
    public required string ItemKey { get; init; }

    public required string Name { get; init; }

    public required string Slot { get; init; }

    public required int Act { get; init; }

    public string Region { get; init; } = string.Empty;

    public string Acquisition { get; init; } = string.Empty;

    [JsonPropertyName("game_x")]
    public int? GameX { get; init; }

    [JsonPropertyName("game_y")]
    public int? GameY { get; init; }

    [JsonPropertyName("map_objective")]
    public bool MapObjective { get; init; } = true;

    public string Effect { get; init; } = string.Empty;

    public string Acquire { get; init; } = string.Empty;

    public string Wiki { get; init; } = string.Empty;

    public string Icon { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;
}

public sealed record TimedEvent(
    string Id,
    string Name,
    string Kind,
    string Trigger,
    string Deadline,
    string Consequence,
    string Severity,
    string Source);

public sealed record ActGuideSummary
{
    public required int Act { get; init; }

    public required string Title { get; init; }

    [JsonPropertyName("route_available")]
    public required bool RouteAvailable { get; init; }

    [JsonPropertyName("local_map_available")]
    public required bool LocalMapAvailable { get; init; }

    [JsonPropertyName("map_name")]
    public required string MapName { get; init; }

    [JsonPropertyName("map_url")]
    public required string MapUrl { get; init; }

    [JsonPropertyName("equipment_file")]
    public required string EquipmentFile { get; init; }

    [JsonPropertyName("coordinate_system")]
    public required string CoordinateSystem { get; init; }

    [JsonPropertyName("coordinate_note")]
    public required string CoordinateNote { get; init; }

    [JsonPropertyName("equipment_count")]
    public required int EquipmentCount { get; init; }

    [JsonIgnore]
    public ActMapHandoff? MapHandoff =>
        LocalMapAvailable
            ? new ActMapHandoff.Local()
            : Uri.TryCreate(MapUrl, UriKind.Absolute, out var uri)
                ? new ActMapHandoff.External(uri)
                : null;
}

public abstract record ActMapHandoff
{
    private ActMapHandoff()
    {
    }

    public sealed record Local : ActMapHandoff;

    public sealed record External(Uri Uri) : ActMapHandoff;
}
