using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;

namespace BG3HonorAssistant.Core.Chat;

public enum ChatScope
{
    Current,
    Route,
    Party,
}

public sealed record ChatMessage(string Role, string Content);

public sealed record ChatSource(string Title, string Url, string Snippet);

public sealed record ChatPrompt(
    IReadOnlyList<ChatMessage> Messages,
    IReadOnlyList<ChatSource> Sources);

public static class ChatPromptBuilder
{
    private static readonly JsonSerializerOptions Json = CreateJson();

    public static JsonNode ResponseSchema { get; } = JsonNode.Parse(
        """
        {
          "type": "object",
          "properties": {
            "answer": { "type": "string" }
          },
          "required": ["answer"],
          "additionalProperties": false
        }
        """)!;

    public static ChatPrompt Build(
        HonorRun run,
        RoutePayload payload,
        WalkthroughStep? currentStep,
        IReadOnlyList<PartyMember> activeParty,
        string question,
        ChatScope scope,
        IReadOnlyList<ChatMessage> history)
    {
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(payload);
        ArgumentNullException.ThrowIfNull(activeParty);
        ArgumentException.ThrowIfNullOrWhiteSpace(question);
        ArgumentNullException.ThrowIfNull(history);
        if (!payload.RouteAvailable)
        {
            throw new InvalidOperationException(
                $"Reviewed route chat is not available for Act {run.SelectedAct ?? payload.Act} yet.");
        }

        var candidates = scope == ChatScope.Current
            ? CurrentCandidates(payload.Walkthrough, currentStep)
            : payload.Walkthrough;
        var ranked = Rank(candidates, currentStep?.Id, question)
            .Take(scope == ChatScope.Current ? 5 : 14)
            .ToList();
        var guideJson = JsonSerializer.Serialize(ranked, Json);
        var rosterJson = JsonSerializer.Serialize(activeParty, Json);
        var lowestLevel = activeParty.Count == 0
            ? 1
            : activeParty.Min(member => member.Level);
        var outcomes = string.Join(
            ", ",
            (run.StoryOutcomes ?? [])
            .OrderBy(outcome => outcome, StringComparer.Ordinal));
        var system =
            $"""
             You are a concise Baldur's Gate 3 assistant for a {run.Difficulty} run. Answer only from the bundled guide facts and run state below. Never invent mechanics, locations, rewards, or completion state. Clearly say when the guide does not establish an answer. Prioritize irreversible risks and the safest next action. Only treat legendary actions and single-save consequences as active when difficulty is Honour. Keep the answer under 220 words. Return strict JSON matching the supplied schema.

             RUN STATE
             Difficulty: {run.Difficulty}
             Act: {run.SelectedAct ?? payload.Act}
             Region: {run.MapRegion}
             Lowest active party level: {lowestLevel}
             Story outcomes: {outcomes}
             Party: {rosterJson}

             BUNDLED GUIDE FACTS
             {guideJson}
             """;
        var recentHistory = history
            .Where(
                message =>
                    message.Role is "user" or "assistant" &&
                    !string.IsNullOrWhiteSpace(message.Content))
            .TakeLast(8)
            .ToList();
        var messages = new List<ChatMessage>(recentHistory.Count + 2)
        {
            new("system", system),
        };
        messages.AddRange(recentHistory);
        messages.Add(new ChatMessage("user", question.Trim()));
        return new ChatPrompt(messages, Sources(ranked));
    }

    public static string DecodeAnswer(string structuredContent)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(structuredContent);
        try
        {
            using var document = JsonDocument.Parse(structuredContent);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("answer", out var answer) &&
                answer.ValueKind == JsonValueKind.String &&
                answer.GetString()?.Trim() is { Length: > 0 } text)
            {
                return text;
            }
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException(
                "OpenRouter returned an invalid structured chat response.",
                exception);
        }

        throw new InvalidOperationException(
            "OpenRouter returned an invalid structured chat response.");
    }

    private static IReadOnlyList<WalkthroughStep> CurrentCandidates(
        IReadOnlyList<WalkthroughStep> walkthrough,
        WalkthroughStep? currentStep)
    {
        if (currentStep is null)
        {
            return walkthrough.Take(8).ToList();
        }

        var index = walkthrough
            .Select((step, index) => (step, index))
            .FirstOrDefault(item => item.step.Id == currentStep.Id)
            .index;
        var start = Math.Max(0, index - 2);
        return walkthrough
            .Skip(start)
            .Take(Math.Min(walkthrough.Count, index + 3) - start)
            .ToList();
    }

    private static IEnumerable<WalkthroughStep> Rank(
        IReadOnlyList<WalkthroughStep> candidates,
        string? currentId,
        string question)
    {
        var terms = Regex
            .Split(question.ToLowerInvariant(), @"[^\p{L}\p{N}]+")
            .Where(term => term.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
        return candidates
            .Select(
                step =>
                {
                    var text =
                        $"{step.Title} {step.Summary} {step.Why} {step.Avoid} {string.Join(' ', step.Rewards)}"
                            .ToLowerInvariant();
                    var score = terms.Count(text.Contains);
                    if (step.Id == currentId)
                    {
                        score += 100;
                    }

                    return (Step: step, Score: score);
                })
            .OrderByDescending(item => item.Score)
            .ThenBy(item => item.Step.Order)
            .Select(item => item.Step);
    }

    private static IReadOnlyList<ChatSource> Sources(
        IReadOnlyList<WalkthroughStep> steps)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return steps
            .Where(
                step =>
                    !string.IsNullOrWhiteSpace(step.SourceUrl) &&
                    seen.Add(step.SourceUrl))
            .Select(
                step =>
                    new ChatSource(
                        string.IsNullOrWhiteSpace(step.SourceLabel)
                            ? step.Title
                            : step.SourceLabel,
                        step.SourceUrl,
                        step.Summary))
            .ToList();
    }

    private static JsonSerializerOptions CreateJson()
    {
        var options = JsonDefaults.Create();
        options.WriteIndented = false;
        return options;
    }
}
