using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public sealed record WalkthroughDependency(
    [property: JsonPropertyName("step_id")] string StepId,
    string Kind,
    string Reason,
    [property: JsonPropertyName("required_outcome")] string? RequiredOutcome = null);
