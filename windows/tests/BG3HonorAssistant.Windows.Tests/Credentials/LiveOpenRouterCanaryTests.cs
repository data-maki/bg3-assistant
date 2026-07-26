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

        var key = Environment.GetEnvironmentVariable("OPENROUTER_API_KEY");
        Assert.False(string.IsNullOrWhiteSpace(key));
        var store = new CredentialStore();
        store.Save(key);
        Assert.Equal(key, store.Read());

        var client = new OpenRouterClient(AssistantHttpClient.Instance);
        var result = await client.CompleteAsync(
            key,
            [
                new OpenRouterMessage(
                    "system",
                    "Return strict JSON matching the supplied schema. Put the single word OK in answer."),
                new OpenRouterMessage("user", "Windows release canary."),
            ],
            ChatPromptBuilder.ResponseSchema,
            "windows_release_canary",
            512,
            CancellationToken.None);

        Assert.Equal(
            "OK",
            ChatPromptBuilder.DecodeAnswer(result).ToUpperInvariant());
    }
}
