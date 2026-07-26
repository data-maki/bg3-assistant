using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using BG3HonorAssistant.Infrastructure.OpenRouter;

namespace BG3HonorAssistant.Infrastructure.Tests.OpenRouter;

public sealed class OpenRouterClientTests
{
    [Fact]
    public async Task SendsPinnedTextOnlyStructuredRequestAndParsesAnswer()
    {
        var handler = new RecordingHandler(
            _ => JsonResponse(
                """
                {"choices":[{"message":{"content":"{\"answer\":\"Stay high.\"}"}}]}
                """));
        var client = CreateClient(handler);

        var result = await client.CompleteAsync(
            "temporary-secret",
            [
                new OpenRouterMessage("system", "Use only guide facts."),
                new OpenRouterMessage("user", "What next?"),
            ],
            JsonNode.Parse(
                """
                {"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"],"additionalProperties":false}
                """));

        Assert.Equal("""{"answer":"Stay high."}""", result);
        Assert.NotNull(handler.Request);
        Assert.Equal(HttpMethod.Post, handler.Request!.Method);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal("temporary-secret", handler.AuthorizationParameter);
        using var document = JsonDocument.Parse(handler.Body!);
        var root = document.RootElement;
        Assert.Equal(OpenRouterClient.Model, root.GetProperty("model").GetString());
        Assert.Equal(JsonValueKind.String, root.GetProperty("messages")[1].GetProperty("content").ValueKind);
        Assert.True(
            root.GetProperty("provider").GetProperty("require_parameters").GetBoolean());
        Assert.Equal(
            "minimal",
            root.GetProperty("reasoning").GetProperty("effort").GetString());
        Assert.True(
            root.GetProperty("reasoning").GetProperty("exclude").GetBoolean());
        Assert.Equal(
            "json_schema",
            root.GetProperty("response_format").GetProperty("type").GetString());
        Assert.DoesNotContain("image", handler.Body!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task JoinsTextPartsInProviderResponse()
    {
        var handler = new RecordingHandler(
            _ => JsonResponse(
                """
                {"choices":[{"message":{"content":[{"type":"text","text":"one"},{"type":"text","text":" two"}]}}]}
                """));
        var client = CreateClient(handler);

        var result = await client.CompleteAsync(
            "key",
            [new OpenRouterMessage("user", "question")]);

        Assert.Equal("one two", result);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, OpenRouterFailure.Authentication)]
    [InlineData(HttpStatusCode.PaymentRequired, OpenRouterFailure.Credits)]
    [InlineData(HttpStatusCode.Forbidden, OpenRouterFailure.Forbidden)]
    [InlineData(HttpStatusCode.RequestTimeout, OpenRouterFailure.Timeout)]
    [InlineData(HttpStatusCode.TooManyRequests, OpenRouterFailure.RateLimited)]
    [InlineData(HttpStatusCode.NotFound, OpenRouterFailure.ModelUnavailable)]
    [InlineData(HttpStatusCode.BadGateway, OpenRouterFailure.Provider)]
    [InlineData(HttpStatusCode.ServiceUnavailable, OpenRouterFailure.Provider)]
    [InlineData(HttpStatusCode.BadRequest, OpenRouterFailure.Request)]
    public async Task MapsProviderStatusToExplicitFailure(
        HttpStatusCode statusCode,
        OpenRouterFailure expected)
    {
        const string key = "sk-or-secret-never-show";
        const string prompt = "private prompt never show";
        var handler = new RecordingHandler(
            _ => new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(
                        new { error = new { message = $"{key} {prompt}" } }),
                    Encoding.UTF8,
                    "application/json"),
            });
        var client = CreateClient(handler);

        var exception = await Assert.ThrowsAsync<OpenRouterException>(
            () => client.CompleteAsync(
                key,
                [new OpenRouterMessage("user", prompt)]));

        Assert.Equal(expected, exception.Failure);
        Assert.DoesNotContain(key, exception.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(prompt, exception.ToString(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("""{"choices":[]}""")]
    [InlineData("""{"choices":[{"message":{"content":""}}]}""")]
    [InlineData("not json")]
    public async Task RejectsMalformedOrEmptyResponses(string responseBody)
    {
        var handler = new RecordingHandler(_ => JsonResponse(responseBody));
        var client = CreateClient(handler);

        var exception = await Assert.ThrowsAsync<OpenRouterException>(
            () => client.CompleteAsync(
                "key",
                [new OpenRouterMessage("user", "question")]));

        Assert.Equal(OpenRouterFailure.InvalidResponse, exception.Failure);
    }

    [Fact]
    public async Task ReportsTimeoutWithoutFallbackAnswer()
    {
        var handler = new RecordingHandler(
            async (_, cancellationToken) =>
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                throw new InvalidOperationException();
            });
        var client = CreateClient(handler, TimeSpan.FromMilliseconds(25));

        var exception = await Assert.ThrowsAsync<OpenRouterException>(
            () => client.CompleteAsync(
                "key",
                [new OpenRouterMessage("user", "question")]));

        Assert.Equal(OpenRouterFailure.Timeout, exception.Failure);
        Assert.Contains("timed out", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    private static OpenRouterClient CreateClient(
        HttpMessageHandler handler,
        TimeSpan? timeout = null) =>
        new(
            new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan },
            new Uri("https://openrouter.test/api/v1/chat/completions"),
            timeout);

    private static HttpResponseMessage JsonResponse(string body) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };

    private sealed class RecordingHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>>
            response;

        internal RecordingHandler(Func<HttpRequestMessage, HttpResponseMessage> response)
            : this((request, _) => Task.FromResult(response(request)))
        {
        }

        internal RecordingHandler(
            Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> response)
        {
            this.response = response;
        }

        internal HttpRequestMessage? Request { get; private set; }

        internal string? Body { get; private set; }

        internal string? AuthorizationScheme { get; private set; }

        internal string? AuthorizationParameter { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Request = request;
            Body = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            return await response(request, cancellationToken);
        }
    }
}
