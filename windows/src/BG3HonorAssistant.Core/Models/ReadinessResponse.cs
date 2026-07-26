namespace BG3HonorAssistant.Core.Models;

public sealed record ReadinessResponse(
    string Status,
    int PartyLevel,
    int MinimumLevel,
    IReadOnlyList<string> Blockers,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<string> NextActions);

public sealed record LevelActivityPlan(
    string ActivityLabel,
    string PhaseName,
    RouteCheckpoint Recommendation,
    IReadOnlyList<RouteCheckpoint> SafeXp,
    RouteCheckpoint? CoreChallenge,
    string GateAdvice);
