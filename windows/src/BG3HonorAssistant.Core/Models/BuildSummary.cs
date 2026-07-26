using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public sealed record BuildLevel(
    int Level,
    string Take,
    [property: JsonPropertyName("subclass_choice")] string SubclassChoice,
    string Choices,
    string Tactics,
    string Confidence,
    [property: JsonPropertyName("ability_score_reset")] AbilityScores? AbilityScoreReset = null);

public sealed record BuildSummary
{
    public required string Id { get; init; }

    public required string Name { get; init; }

    [JsonPropertyName("honor_status")]
    public string HonorStatus { get; init; } = string.Empty;

    public string Role { get; init; } = string.Empty;

    [JsonPropertyName("final_split")]
    public string FinalSplit { get; init; } = string.Empty;

    [JsonPropertyName("play_pattern")]
    public string PlayPattern { get; init; } = string.Empty;

    [JsonPropertyName("class_progression")]
    public string ClassProgression { get; init; } = string.Empty;

    [JsonPropertyName("starting_abilities")]
    public string StartingAbilities { get; init; } = string.Empty;

    [JsonPropertyName("starting_ability_scores")]
    public AbilityScores? StartingAbilityScores { get; init; }

    [JsonPropertyName("target_ability_scores")]
    public AbilityScores? TargetAbilityScores { get; init; }

    [JsonPropertyName("target_ability_note")]
    public string? TargetAbilityNote { get; init; }

    [JsonPropertyName("ability_setups")]
    public IReadOnlyList<AbilitySetupPlan>? AbilitySetups { get; init; }

    [JsonPropertyName("ability_sources")]
    public IReadOnlyList<AbilityPlanSource>? AbilitySources { get; init; }

    public string Caveat { get; init; } = string.Empty;

    public string Source { get; init; } = string.Empty;

    public IReadOnlyList<BuildLevel> Levels { get; init; } = [];

    public IReadOnlyList<BuildGear> Gear { get; init; } = [];
}
