using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Windows.Credentials;

namespace BG3HonorAssistant.Windows.Tests.Credentials;

public sealed class LiveOpenRouterCanaryTests
{
    [Fact]
    [Trait("Category", "LiveOpenRouter")]
    public async Task SavedCredentialReturnsRealPinnedModelResponseWhenEnabled()
    {
        if (Environment.GetEnvironmentVariable("BG3_RUN_LIVE_OPENROUTER") != "1")
        {
            return;
        }

        var store = new CredentialStore();
        var key = store.Read();
        Assert.False(string.IsNullOrWhiteSpace(key));

        var client = new OpenRouterClient(AssistantHttpClient.Instance);
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var result = await client.CompleteTextAsync(
            key!,
            [
                new OpenRouterMessage(
                    "system",
                    "Reply with the single word OK."),
                new OpenRouterMessage("user", "Windows release canary."),
            ],
            maxTokens: 512,
            cancellationToken: cancellation.Token);

        Assert.Equal("OK", result.Trim().ToUpperInvariant());
    }
}
