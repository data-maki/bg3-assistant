using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BG3HonorAssistant.Infrastructure.OpenRouter;

public sealed record OpenRouterMessage(string Role, string Content);

public interface IOpenRouterClient
{
    Task<string> CompleteTextAsync(
        string apiKey,
        IReadOnlyList<OpenRouterMessage> messages,
        int maxTokens = 1_200,
        CancellationToken cancellationToken = default);

    Task<string> CompleteJsonAsync(
        string apiKey,
        IReadOnlyList<OpenRouterMessage> messages,
        JsonNode responseSchema,
        string schemaName,
        int maxTokens = 1_200,
        CancellationToken cancellationToken = default);
}

public sealed class OpenRouterClient : IOpenRouterClient
{
    public const string Model = "google/gemini-3.6-flash";
    public const string ModelDisplayName = "Google Gemini 3.6 Flash";
    public const string Endpoint =
        "https://openrouter.ai/api/v1/chat/completions";

    private const int MaximumResponseBytes = 1_000_000;
    private static readonly Uri ProductionEndpoint = new(Endpoint);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly HttpClient httpClient;
    private readonly Uri endpoint;
    private readonly TimeSpan timeout;

    public OpenRouterClient(
        HttpClient httpClient,
        Uri? endpoint = null,
        TimeSpan? timeout = null)
    {
        this.httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        this.endpoint = ValidateEndpoint(endpoint ?? ProductionEndpoint);
        this.timeout = timeout ?? TimeSpan.FromSeconds(90);
    }

    public Task<string> CompleteTextAsync(
        string apiKey,
        IReadOnlyList<OpenRouterMessage> messages,
        int maxTokens = 1_200,
        CancellationToken cancellationToken = default) =>
        CompleteAsync(
            apiKey,
            messages,
            responseSchema: null,
            schemaName: "assistant_response",
            maxTokens: maxTokens,
            cancellationToken: cancellationToken);

    public Task<string> CompleteJsonAsync(
        string apiKey,
        IReadOnlyList<OpenRouterMessage> messages,
        JsonNode responseSchema,
        string schemaName,
        int maxTokens = 1_200,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(responseSchema);
        ArgumentException.ThrowIfNullOrWhiteSpace(schemaName);
        return CompleteAsync(
            apiKey,
            messages,
            responseSchema,
            schemaName,
            maxTokens,
            cancellationToken);
    }

    private async Task<string> CompleteAsync(
        string apiKey,
        IReadOnlyList<OpenRouterMessage> messages,
        JsonNode? responseSchema,
        string schemaName,
        int maxTokens,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        ArgumentNullException.ThrowIfNull(messages);
        if (messages.Count == 0)
        {
            throw new ArgumentException("At least one message is required.", nameof(messages));
        }

        if (messages.Any(
                message =>
                    message.Role is not ("system" or "user" or "assistant") ||
                    string.IsNullOrWhiteSpace(message.Content)))
        {
            throw new ArgumentException(
                "Messages must have a supported role and non-empty text.",
                nameof(messages));
        }

        if (maxTokens is < 1 or > 4_096)
        {
            throw new ArgumentOutOfRangeException(nameof(maxTokens));
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        request.Headers.TryAddWithoutValidation(
            "HTTP-Referer",
            "https://github.com/data-maki/bg3-assistant");
        request.Headers.TryAddWithoutValidation(
            "X-Title",
            "BG3 Honor Assistant for Windows");

        var body = new JsonObject
        {
            ["model"] = Model,
            ["messages"] = new JsonArray(
                messages.Select(
                        message =>
                            (JsonNode)new JsonObject
                            {
                                ["role"] = message.Role,
                                ["content"] = message.Content,
                            })
                    .ToArray()),
            ["temperature"] = 0.1,
            ["max_tokens"] = maxTokens,
            ["provider"] = new JsonObject
            {
                ["require_parameters"] = responseSchema is not null,
            },
            ["reasoning"] = new JsonObject
            {
                ["effort"] = "minimal",
                ["exclude"] = true,
            },
        };
        if (responseSchema is not null)
        {
            body["response_format"] = new JsonObject
            {
                ["type"] = "json_schema",
                ["json_schema"] = new JsonObject
                {
                    ["name"] = schemaName,
                    ["strict"] = true,
                    ["schema"] = responseSchema.DeepClone(),
                },
            };
        }

        request.Content = new StringContent(
            body.ToJsonString(Json),
            Encoding.UTF8,
            "application/json");

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeoutSource.CancelAfter(timeout);

        HttpResponseMessage response;
        try
        {
            response = await httpClient
                .SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeoutSource.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OpenRouterException(
                OpenRouterFailure.Timeout,
                "OpenRouter did not respond before the request timed out.",
                innerException: exception);
        }
        catch (Exception exception) when (
            exception is HttpRequestException or IOException)
        {
            throw new OpenRouterException(
                OpenRouterFailure.Network,
                "OpenRouter could not be reached. Check the internet connection and try again.",
                innerException: exception);
        }

        using (response)
        {
            byte[] data;
            try
            {
                data = await ReadBoundedAsync(
                        response.Content,
                        MaximumResponseBytes,
                        timeoutSource.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException exception)
                when (!cancellationToken.IsCancellationRequested)
            {
                throw new OpenRouterException(
                    OpenRouterFailure.Timeout,
                    "OpenRouter did not finish its response before the request timed out.",
                    innerException: exception);
            }
            catch (Exception exception) when (
                exception is HttpRequestException or IOException)
            {
                throw new OpenRouterException(
                    OpenRouterFailure.Network,
                    "The OpenRouter response could not be read.",
                    innerException: exception);
            }

            if (!response.IsSuccessStatusCode)
            {
                throw CreateProviderFailure(response.StatusCode);
            }

            try
            {
                using var document = JsonDocument.Parse(data);
                var root = document.RootElement;
                if (root.TryGetProperty("error", out var error))
                {
                    _ = error;
                    throw new OpenRouterException(
                        OpenRouterFailure.Provider,
                        "OpenRouter reported a provider error.");
                }

                if (!root.TryGetProperty("choices", out var choices) ||
                    choices.ValueKind != JsonValueKind.Array ||
                    choices.GetArrayLength() == 0 ||
                    !choices[0].TryGetProperty("message", out var message) ||
                    !message.TryGetProperty("content", out var content))
                {
                    throw InvalidResponse();
                }

                var text = ExtractContent(content);
                if (string.IsNullOrWhiteSpace(text))
                {
                    if (choices[0].TryGetProperty("finish_reason", out var finishReason) &&
                        finishReason.ValueKind == JsonValueKind.String &&
                        finishReason.GetString() == "length")
                    {
                        throw new OpenRouterException(
                            OpenRouterFailure.Provider,
                            "The pinned model exhausted its output limit before returning an answer.");
                    }

                    throw InvalidResponse();
                }

                return text;
            }
            catch (OpenRouterException)
            {
                throw;
            }
            catch (JsonException exception)
            {
                throw InvalidResponse(exception);
            }
        }
    }

    private static string ExtractContent(JsonElement content)
    {
        if (content.ValueKind == JsonValueKind.String)
        {
            return content.GetString() ?? string.Empty;
        }

        if (content.ValueKind != JsonValueKind.Array)
        {
            return string.Empty;
        }

        var builder = new StringBuilder();
        foreach (var part in content.EnumerateArray())
        {
            if (part.ValueKind == JsonValueKind.Object &&
                part.TryGetProperty("text", out var text) &&
                text.ValueKind == JsonValueKind.String)
            {
                builder.Append(text.GetString());
            }
        }

        return builder.ToString();
    }

    private static OpenRouterException CreateProviderFailure(HttpStatusCode statusCode)
    {
        var status = (int)statusCode;
        var failure = status switch
        {
            401 => OpenRouterFailure.Authentication,
            402 => OpenRouterFailure.Credits,
            403 => OpenRouterFailure.Forbidden,
            408 or 504 => OpenRouterFailure.Timeout,
            429 => OpenRouterFailure.RateLimited,
            404 => OpenRouterFailure.ModelUnavailable,
            >= 500 and <= 599 => OpenRouterFailure.Provider,
            _ => OpenRouterFailure.Request,
        };
        var fallback = failure switch
        {
            OpenRouterFailure.Authentication =>
                "OpenRouter rejected the API key. Replace it in Settings and try again.",
            OpenRouterFailure.Credits =>
                "The OpenRouter account has insufficient credits.",
            OpenRouterFailure.Forbidden =>
                "OpenRouter denied this request for the configured key or provider.",
            OpenRouterFailure.Timeout =>
                "OpenRouter timed out while processing the request.",
            OpenRouterFailure.RateLimited =>
                "OpenRouter is rate limiting this key. Wait and try again.",
            OpenRouterFailure.ModelUnavailable =>
                $"The pinned model {Model} is unavailable.",
            OpenRouterFailure.Provider =>
                "OpenRouter could not route the pinned model to an available provider.",
            _ => $"OpenRouter rejected the request with HTTP {status}.",
        };

        return new OpenRouterException(
            failure,
            fallback,
            statusCode);
    }

    private static Uri ValidateEndpoint(Uri endpoint)
    {
        ArgumentNullException.ThrowIfNull(endpoint);
        if (!endpoint.IsAbsoluteUri ||
            !string.Equals(
                endpoint.Scheme,
                Uri.UriSchemeHttps,
                StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(
                endpoint.IdnHost,
                ProductionEndpoint.IdnHost,
                StringComparison.OrdinalIgnoreCase) ||
            endpoint.Port != 443 ||
            !string.IsNullOrEmpty(endpoint.UserInfo) ||
            !string.Equals(
                endpoint.AbsolutePath,
                ProductionEndpoint.AbsolutePath,
                StringComparison.Ordinal) ||
            !string.IsNullOrEmpty(endpoint.Query) ||
            !string.IsNullOrEmpty(endpoint.Fragment))
        {
            throw new ArgumentException(
                "OpenRouter requests must use the pinned direct HTTPS production endpoint.",
                nameof(endpoint));
        }

        return endpoint;
    }

    private static async Task<byte[]> ReadBoundedAsync(
        HttpContent content,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength is > MaximumResponseBytes)
        {
            throw InvalidResponse();
        }

        await using var source = await content
            .ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        using var destination = new MemoryStream();
        var buffer = new byte[16_384];
        while (true)
        {
            var read = await source
                .ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)
                .ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            if (destination.Length + read > maximumBytes)
            {
                throw InvalidResponse();
            }

            destination.Write(buffer, 0, read);
        }

        return destination.ToArray();
    }

    private static OpenRouterException InvalidResponse(Exception? innerException = null) =>
        new(
            OpenRouterFailure.InvalidResponse,
            "OpenRouter returned an invalid response.",
            innerException: innerException);
}

public enum OpenRouterFailure
{
    Authentication,
    Credits,
    Forbidden,
    Timeout,
    RateLimited,
    ModelUnavailable,
    Provider,
    Request,
    Network,
    InvalidResponse,
}

public sealed class OpenRouterException : Exception
{
    public OpenRouterException(
        OpenRouterFailure failure,
        string message,
        HttpStatusCode? statusCode = null,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Failure = failure;
        StatusCode = statusCode;
    }

    public OpenRouterFailure Failure { get; }

    public HttpStatusCode? StatusCode { get; }
}
