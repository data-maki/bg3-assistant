using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;
using AngleSharp.Html.Parser;
using BG3HonorAssistant.Infrastructure.Networking;
using UglyToad.PdfPig;

namespace BG3HonorAssistant.Infrastructure.BuildImport;

public sealed record BuildImportSource(Uri Url, string Text);

public interface IBuildSourceLoader
{
    Task<BuildImportSource> LoadAsync(
        string rawUrl,
        CancellationToken cancellationToken = default);
}

public sealed partial class SecureBuildSourceLoader : IBuildSourceLoader
{
    public const int MaximumDownloadBytes = 5_000_000;
    public const int MaximumTextCharacters = 60_000;
    public const int MaximumRedirects = 5;

    private static readonly MediaTypeWithQualityHeaderValue[] AcceptedMediaTypes =
    [
        new("text/html"),
        new("application/xhtml+xml"),
        new("application/pdf"),
        new("text/plain"),
    ];

    private readonly HttpClient httpClient;
    private readonly IHostAddressResolver resolver;
    private readonly TimeSpan timeout;

    public SecureBuildSourceLoader(
        HttpClient httpClient,
        IHostAddressResolver? resolver = null,
        TimeSpan? timeout = null)
    {
        this.httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        this.resolver = resolver ?? new SystemHostAddressResolver();
        this.timeout = timeout ?? TimeSpan.FromSeconds(30);
    }

    public async Task<BuildImportSource> LoadAsync(
        string rawUrl,
        CancellationToken cancellationToken = default)
    {
        var current = PublicNetworkPolicy.ValidateHttpsUri(rawUrl);
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeoutSource.CancelAfter(timeout);

        for (var redirectCount = 0; ; redirectCount++)
        {
            await PublicNetworkPolicy.ResolvePublicAsync(
                    current.IdnHost,
                    resolver,
                    timeoutSource.Token)
                .ConfigureAwait(false);

            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            request.Headers.UserAgent.ParseAdd("BG3HonorAssistant/1.0 (Windows)");
            foreach (var mediaType in AcceptedMediaTypes)
            {
                request.Headers.Accept.Add(mediaType);
            }

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
            catch (OperationCanceledException exception)
                when (!cancellationToken.IsCancellationRequested)
            {
                throw new BuildImportSourceException(
                    BuildImportSourceFailure.Timeout,
                    "The build page did not respond before the import timed out.",
                    exception);
            }
            catch (Exception exception) when (
                exception is HttpRequestException or IOException)
            {
                throw new BuildImportSourceException(
                    BuildImportSourceFailure.DownloadFailed,
                    "The build page could not be downloaded.",
                    exception);
            }

            using (response)
            {
                if (IsRedirect(response.StatusCode))
                {
                    if (redirectCount >= MaximumRedirects ||
                        response.Headers.Location is not { } location)
                    {
                        throw new BuildImportSourceException(
                            BuildImportSourceFailure.RedirectRejected,
                            "The build page used too many or invalid redirects.");
                    }

                    current = PublicNetworkPolicy.ValidateHttpsUri(
                        location.IsAbsoluteUri ? location : new Uri(current, location));
                    continue;
                }

                if (!response.IsSuccessStatusCode)
                {
                    throw new BuildImportSourceException(
                        BuildImportSourceFailure.DownloadFailed,
                        $"The build page returned HTTP {(int)response.StatusCode}.");
                }

                byte[] bytes;
                string text;
                try
                {
                    bytes = await ReadBoundedAsync(
                            response.Content,
                            timeoutSource.Token)
                        .ConfigureAwait(false);
                    text = await ExtractTextAsync(
                            current,
                            response.Content.Headers.ContentType?.MediaType,
                            bytes,
                            timeoutSource.Token)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException exception)
                    when (!cancellationToken.IsCancellationRequested)
                {
                    throw new BuildImportSourceException(
                        BuildImportSourceFailure.Timeout,
                        "The build page did not finish before the import timed out.",
                        exception);
                }
                catch (Exception exception) when (
                    exception is HttpRequestException or IOException)
                {
                    throw new BuildImportSourceException(
                        BuildImportSourceFailure.DownloadFailed,
                        "The build page response could not be read.",
                        exception);
                }

                var normalized = Normalize(text);
                if (normalized.Length < 100)
                {
                    throw new BuildImportSourceException(
                        BuildImportSourceFailure.UnreadableSource,
                        "The build page did not contain enough readable text.");
                }

                return new BuildImportSource(
                    current,
                    normalized[..Math.Min(normalized.Length, MaximumTextCharacters)]);
            }
        }
    }

    private static bool IsRedirect(HttpStatusCode statusCode) =>
        statusCode is
            HttpStatusCode.MovedPermanently or
            HttpStatusCode.Redirect or
            HttpStatusCode.RedirectMethod or
            HttpStatusCode.TemporaryRedirect or
            HttpStatusCode.PermanentRedirect;

    private static async Task<byte[]> ReadBoundedAsync(
        HttpContent content,
        CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength is > MaximumDownloadBytes)
        {
            throw new BuildImportSourceException(
                BuildImportSourceFailure.SourceTooLarge,
                "The build page is larger than 5 MB.");
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

            if (destination.Length + read > MaximumDownloadBytes)
            {
                throw new BuildImportSourceException(
                    BuildImportSourceFailure.SourceTooLarge,
                    "The build page is larger than 5 MB.");
            }

            destination.Write(buffer, 0, read);
        }

        return destination.ToArray();
    }

    private static async Task<string> ExtractTextAsync(
        Uri source,
        string? mediaType,
        byte[] bytes,
        CancellationToken cancellationToken)
    {
        var normalizedMediaType = mediaType?.ToLowerInvariant();
        var isPdf =
            normalizedMediaType == "application/pdf" ||
            source.AbsolutePath.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase);
        if (isPdf)
        {
            try
            {
                using var pdfDocument = PdfDocument.Open(bytes);
                return string.Join(
                    '\n',
                    pdfDocument.GetPages().Select(page => page.Text));
            }
            catch (Exception exception) when (
                exception is InvalidOperationException or IOException or ArgumentException)
            {
                throw new BuildImportSourceException(
                    BuildImportSourceFailure.UnreadableSource,
                    "The PDF build guide could not be read.",
                    exception);
            }
        }

        if (normalizedMediaType == "text/plain")
        {
            return Encoding.UTF8.GetString(bytes);
        }

        if (normalizedMediaType is not (
                null or
                "text/html" or
                "application/xhtml+xml"))
        {
            throw new BuildImportSourceException(
                BuildImportSourceFailure.UnsupportedContent,
                "The build source must be HTML, plain text, or PDF.");
        }

        var html = Encoding.UTF8.GetString(bytes);
        var parser = new HtmlParser();
        var htmlDocument = await parser
            .ParseDocumentAsync(html, cancellationToken)
            .ConfigureAwait(false);
        foreach (var element in htmlDocument.QuerySelectorAll(
                     "script,style,noscript,svg,canvas,template"))
        {
            element.Remove();
        }

        return htmlDocument.Body?.TextContent ?? htmlDocument.DocumentElement.TextContent;
    }

    private static string Normalize(string text) =>
        ExcessHorizontalWhitespace()
            .Replace(
                ExcessBlankLines().Replace(text.ReplaceLineEndings("\n"), "\n\n"),
                " ")
            .Trim();

    [GeneratedRegex(@"[ \t\f\v]+")]
    private static partial Regex ExcessHorizontalWhitespace();

    [GeneratedRegex(@"\n{3,}")]
    private static partial Regex ExcessBlankLines();
}

public enum BuildImportSourceFailure
{
    Timeout,
    DownloadFailed,
    SourceTooLarge,
    UnsupportedContent,
    UnreadableSource,
    RedirectRejected,
}

public sealed class BuildImportSourceException : Exception
{
    public BuildImportSourceException(
        BuildImportSourceFailure failure,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Failure = failure;
    }

    public BuildImportSourceFailure Failure { get; }
}
