using System.Net;
using System.Text;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;

namespace BG3HonorAssistant.Infrastructure.Tests.BuildImport;

public sealed class SecureBuildSourceLoaderTests
{
    [Fact]
    public async Task ExtractsNormalizedHtmlAndRemovesExecutableContent()
    {
        var html =
            """
            <html><head><style>.secret { display: none }</style></head>
            <body><h1>Open Hand Monk</h1><script>stealPrompt()</script>
            <p>Level 1 starts as Monk with Dexterity and Wisdom.</p>
            <p>Continue taking Monk levels and use unarmed attacks. This paragraph makes the public build source long enough for validation.</p>
            </body></html>
            """;
        var handler = new QueueHandler(
            Ok(html, "text/html"));
        var loader = CreateLoader(handler);

        var source = await loader.LoadAsync("https://build.example/guide");

        Assert.Equal("https://build.example/guide", source.Url.AbsoluteUri);
        Assert.Contains("Open Hand Monk", source.Text, StringComparison.Ordinal);
        Assert.DoesNotContain("stealPrompt", source.Text, StringComparison.Ordinal);
        Assert.DoesNotContain("display: none", source.Text, StringComparison.Ordinal);
        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task ValidatesEveryRedirectAndRejectsPrivateTarget()
    {
        var handler = new QueueHandler(
            new HttpResponseMessage(HttpStatusCode.Redirect)
            {
                Headers = { Location = new Uri("https://127.0.0.1/secret") },
            });
        var loader = CreateLoader(handler);

        var exception = await Assert.ThrowsAsync<PublicNetworkException>(
            () => loader.LoadAsync("https://build.example/guide"));

        Assert.Equal(PublicNetworkFailure.BlockedAddress, exception.Failure);
        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task FollowsPublicRelativeRedirect()
    {
        var handler = new QueueHandler(
            new HttpResponseMessage(HttpStatusCode.TemporaryRedirect)
            {
                Headers = { Location = new Uri("/final", UriKind.Relative) },
            },
            Ok(
                new string('x', 120),
                "text/plain"));
        var loader = CreateLoader(handler);

        var source = await loader.LoadAsync("https://build.example/start");

        Assert.Equal("https://build.example/final", source.Url.AbsoluteUri);
        Assert.Equal(2, handler.RequestCount);
    }

    [Fact]
    public async Task BlocksPrivateDnsBeforeSending()
    {
        var handler = new QueueHandler(
            Ok(new string('x', 120), "text/plain"));
        var resolver = new StaticResolver(IPAddress.Parse("169.254.169.254"));
        var loader = new SecureBuildSourceLoader(
            new HttpClient(handler),
            resolver);

        var exception = await Assert.ThrowsAsync<PublicNetworkException>(
            () => loader.LoadAsync("https://metadata.attacker.example/build"));

        Assert.Equal(PublicNetworkFailure.BlockedAddress, exception.Failure);
        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task RejectsContentLargerThanFiveMegabytes()
    {
        var handler = new QueueHandler(
            Ok(
                new string('x', SecureBuildSourceLoader.MaximumDownloadBytes + 1),
                "text/plain"));
        var loader = CreateLoader(handler);

        var exception = await Assert.ThrowsAsync<BuildImportSourceException>(
            () => loader.LoadAsync("https://build.example/large"));

        Assert.Equal(BuildImportSourceFailure.SourceTooLarge, exception.Failure);
    }

    [Fact]
    public async Task CapsExtractedTextAtSixtyThousandCharacters()
    {
        var handler = new QueueHandler(
            Ok(new string('x', 70_000), "text/plain"));
        var loader = CreateLoader(handler);

        var source = await loader.LoadAsync("https://build.example/text");

        Assert.Equal(SecureBuildSourceLoader.MaximumTextCharacters, source.Text.Length);
    }

    [Fact]
    public async Task RejectsUnsupportedContentType()
    {
        var handler = new QueueHandler(
            Ok(new string('x', 120), "application/zip"));
        var loader = CreateLoader(handler);

        var exception = await Assert.ThrowsAsync<BuildImportSourceException>(
            () => loader.LoadAsync("https://build.example/archive"));

        Assert.Equal(BuildImportSourceFailure.UnsupportedContent, exception.Failure);
    }

    private static SecureBuildSourceLoader CreateLoader(HttpMessageHandler handler) =>
        new(
            new HttpClient(handler),
            new StaticResolver(IPAddress.Parse("93.184.216.34")));

    private static HttpResponseMessage Ok(string body, string mediaType) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(body, Encoding.UTF8, mediaType),
        };

    private sealed class StaticResolver(params IPAddress[] addresses)
        : IHostAddressResolver
    {
        public Task<IPAddress[]> ResolveAsync(
            string host,
            CancellationToken cancellationToken = default)
        {
            _ = host;
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(addresses);
        }
    }

    private sealed class QueueHandler(params HttpResponseMessage[] responses)
        : HttpMessageHandler
    {
        private readonly Queue<HttpResponseMessage> responses = new(responses);

        internal int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            _ = request;
            cancellationToken.ThrowIfCancellationRequested();
            RequestCount++;
            return Task.FromResult(responses.Dequeue());
        }
    }
}
