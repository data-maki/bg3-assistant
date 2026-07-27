using System.Text.Json;
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

public sealed record ChatPrompt(IReadOnlyList<ChatMessage> Messages);

public static class ChatPromptBuilder
{
    private static readonly JsonSerializerOptions Json = CreateJson();

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
             You are BG3 Overlay's chat assistant, a knowledgeable and practical companion for Baldur's Gate 3.

             Help the player with any Baldur's Gate 3 question, including mechanics, quests, items, builds, combat, exploration, companions, choices, and troubleshooting. Use your general game knowledge to answer. Optional context is additional information, not a boundary on what you may discuss.

             Before answering, silently decide which parts of the optional context are relevant to the question. Use relevant context to personalize the answer. Treat explicit run-state details as facts about this player's save. Treat guide excerpts as supporting information, not as the only permitted source. Ignore irrelevant context completely and never assume the context is complete.

             Address the main point in the first sentence. Default to one to three short paragraphs and no more than 120 words, as if the player were reading on a phone. Use more only when omitting important instructions or consequences would make the answer worse.

             Use plain text paragraphs. You may use **bold** sparingly for the most important words. Apart from bold, do not use Markdown: no headings, bullet or numbered lists, tables, code blocks, or links.

             Include only the explanation, consequences, or steps that help the player act. Distinguish game facts from recommendations. Avoid unnecessary spoilers, but clearly identify irreversible choices when relevant. Mention difficulty, patch, platform, or mod differences only when they materially affect the answer. If uncertain, say so instead of inventing details.

             Use conversation history for follow-up questions. Make a reasonable Baldur's Gate 3 assumption when the question is understandable from context. Ask one concise clarifying question only when answering without it would likely mislead the player.

             You do not have web access, tools, or direct access to the live game beyond information the player or application supplies. Do not imply otherwise. Write concise, natural, practical answers.

             OPTIONAL RUN CONTEXT
             Difficulty: {run.Difficulty}
             Act: {run.SelectedAct ?? payload.Act}
             Region: {run.MapRegion}
             Lowest active party level: {lowestLevel}
             Story outcomes: {outcomes}
             Party: {rosterJson}

             OPTIONAL GUIDE CONTEXT
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
        return new ChatPrompt(messages);
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

    private static JsonSerializerOptions CreateJson()
    {
        var options = JsonDefaults.Create();
        options.WriteIndented = false;
        return options;
    }
}
