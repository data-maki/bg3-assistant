using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public enum StepEncounter
{
    Fight,
    Talk,
    FightAndTalk,
    Explore,
    Pickup,
    Gate,
}

public static class StepEncounterRules
{
    public static StepEncounter Classify(WalkthroughStep step)
    {
        var isFight = step.Kind is "major_fight" or "mini_fight";
        var hasTalk =
            step.Kind is "dialogue" or "decision" ||
            (isFight && step.Decision is not null);
        var canTurnHostile = step.Incident is not null;
        if (isFight)
        {
            return hasTalk ? StepEncounter.FightAndTalk : StepEncounter.Fight;
        }

        if (hasTalk)
        {
            return canTurnHostile ? StepEncounter.FightAndTalk : StepEncounter.Talk;
        }

        return step.Kind switch
        {
            "pickup" => StepEncounter.Pickup,
            "gate" => StepEncounter.Gate,
            _ => StepEncounter.Explore,
        };
    }

    public static string Label(this StepEncounter encounter) =>
        encounter switch
        {
            StepEncounter.Fight => "FIGHT",
            StepEncounter.Talk => "TALK",
            StepEncounter.FightAndTalk => "TALK · FIGHT",
            StepEncounter.Explore => "EXPLORE",
            StepEncounter.Pickup => "PICKUP",
            StepEncounter.Gate => "GATE",
            _ => throw new ArgumentOutOfRangeException(nameof(encounter)),
        };

    public static string? Hint(this StepEncounter encounter) =>
        encounter == StepEncounter.FightAndTalk
            ? "Starts as a conversation — can turn into a fight"
            : null;
}

public sealed record WalkthroughStep
{
    public required string Id { get; init; }

    public required int Order { get; init; }

    public required string Phase { get; init; }

    [JsonPropertyName("phase_order")]
    public required int PhaseOrder { get; init; }

    public required string Title { get; init; }

    public required string Kind { get; init; }

    public required string Importance { get; init; }

    public required string Region { get; init; }

    public required string Area { get; init; }

    [JsonPropertyName("minimum_level")]
    public required int MinimumLevel { get; init; }

    public string Summary { get; init; } = string.Empty;

    public string Avoid { get; init; } = string.Empty;

    public string Why { get; init; } = string.Empty;

    public IReadOnlyList<string> Rewards { get; init; } = [];

    [JsonPropertyName("completion_checks")]
    public IReadOnlyList<string> CompletionChecks { get; init; } = [];

    public IReadOnlyList<string> Prerequisites { get; init; } = [];

    public IReadOnlyList<WalkthroughDependency> Dependencies { get; init; } = [];

    [JsonPropertyName("checkpoint_id")]
    public string? CheckpointId { get; init; }

    [JsonPropertyName("marker_id")]
    public string? MarkerId { get; init; }

    public WalkthroughDecision? Decision { get; init; }

    public IncidentProtocol? Incident { get; init; }

    [JsonPropertyName("risk_reward")]
    public RiskReward? RiskReward { get; init; }

    public string Authority { get; init; } = string.Empty;

    [JsonPropertyName("source_label")]
    public string SourceLabel { get; init; } = string.Empty;

    [JsonPropertyName("source_url")]
    public string SourceUrl { get; init; } = string.Empty;
}
