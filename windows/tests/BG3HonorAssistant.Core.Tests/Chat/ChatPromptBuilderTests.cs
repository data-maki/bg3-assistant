using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Chat;

public sealed class ChatPromptBuilderTests
{
    [Fact]
    public void GroundsCurrentScopeWithCurrentStepAndEightRecentTurns()
    {
        var steps = Enumerable.Range(1, 8)
            .Select(index => Step(index, index == 4 ? "Spectator fight" : $"Step {index}"))
            .ToList();
        var payload = Payload(steps);
        var run = Run();
        var history = Enumerable.Range(1, 10)
            .Select(index => new ChatMessage(
                index % 2 == 0 ? "assistant" : "user",
                $"turn-{index}"))
            .ToList();

        var prompt = ChatPromptBuilder.Build(
            run,
            payload,
            steps[3],
            run.Party,
            "How do I survive the spectator fight?",
            ChatScope.Current,
            history);

        Assert.Equal("system", prompt.Messages[0].Role);
        Assert.Contains("Spectator fight", prompt.Messages[0].Content, StringComparison.Ordinal);
        Assert.DoesNotContain("Step 8", prompt.Messages[0].Content, StringComparison.Ordinal);
        Assert.Equal(10, prompt.Messages.Count);
        Assert.Equal("turn-3", prompt.Messages[1].Content);
        Assert.Equal(
            "How do I survive the spectator fight?",
            prompt.Messages[^1].Content);
        Assert.Equal("https://example.com/source-4", prompt.Sources[0].Url);
    }

    [Fact]
    public void RouteScopeRanksMatchingFactsAndDeduplicatesSources()
    {
        var shared = Step(1, "First") with
        {
            SourceUrl = "https://example.com/shared",
        };
        var match = Step(3, "Poison the goblin camp") with
        {
            SourceUrl = "https://example.com/shared",
        };
        var payload = Payload([shared, Step(2, "Second"), match]);
        var run = Run();

        var prompt = ChatPromptBuilder.Build(
            run,
            payload,
            currentStep: null,
            run.Party,
            "goblin poison",
            ChatScope.Route,
            []);

        var system = prompt.Messages[0].Content;
        Assert.True(
            system.IndexOf("Poison the goblin camp", StringComparison.Ordinal) <
            system.IndexOf("First", StringComparison.Ordinal));
        Assert.Equal(2, prompt.Sources.Count);
    }

    [Fact]
    public void BlocksChatWhenRouteDataIsUnavailable()
    {
        var run = Run();
        run.SelectedAct = 2;
        var payload = Payload([]) with
        {
            Act = 2,
            RouteAvailable = false,
        };

        var exception = Assert.Throws<InvalidOperationException>(
            () => ChatPromptBuilder.Build(
                run,
                payload,
                currentStep: null,
                run.Party,
                "What next?",
                ChatScope.Current,
                []));

        Assert.Contains("Act 2", exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("""{"answer":"Use the bridge."}""", "Use the bridge.")]
    [InlineData("""{"answer":"  Keep distance.  "}""", "Keep distance.")]
    public void DecodesStrictAnswer(string content, string expected)
    {
        Assert.Equal(expected, ChatPromptBuilder.DecodeAnswer(content));
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("""{"answer":""}""")]
    [InlineData("not json")]
    public void RejectsInvalidAnswer(string content)
    {
        Assert.Throws<InvalidOperationException>(
            () => ChatPromptBuilder.DecodeAnswer(content));
    }

    private static HonorRun Run()
    {
        var run = new HonorRun
        {
            Difficulty = RunDifficulty.Honour,
            SelectedAct = 1,
            StoryOutcomes = ["saved-grove"],
        };
        run.NormalizeRoster();
        return run;
    }

    private static RoutePayload Payload(IReadOnlyList<WalkthroughStep> steps) =>
        new()
        {
            Act = 1,
            GuideVersion = "test",
            RouteAvailable = true,
            Walkthrough = steps,
        };

    private static WalkthroughStep Step(int order, string title) =>
        new()
        {
            Id = $"step-{order}",
            Order = order,
            Phase = "phase",
            PhaseOrder = order,
            Title = title,
            Kind = "explore",
            Importance = "core",
            Region = "Wilderness",
            Area = "Test",
            MinimumLevel = 1,
            Summary = $"Summary for {title}.",
            Why = $"Why {title}.",
            Avoid = $"Avoid danger at {title}.",
            Rewards = ["reward"],
            SourceLabel = $"Source {order}",
            SourceUrl = $"https://example.com/source-{order}",
        };
}
