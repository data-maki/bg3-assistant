using System.Net;
using BG3HonorAssistant.Infrastructure.Networking;

namespace BG3HonorAssistant.Infrastructure.Tests.Networking;

public sealed class PublicNetworkPolicyTests
{
    [Theory]
    [InlineData("https://example.com/build")]
    [InlineData("https://example.com:443/build?version=1")]
    [InlineData("https://93.184.216.34/build")]
    public void AcceptsHttpsPort443PublicUrls(string rawUrl)
    {
        var uri = PublicNetworkPolicy.ValidateHttpsUri(rawUrl);

        Assert.Equal("https", uri.Scheme);
        Assert.Equal(443, uri.Port);
    }

    [Theory]
    [InlineData("http://example.com/build")]
    [InlineData("https://example.com:444/build")]
    [InlineData("https://user:pass@example.com/build")]
    [InlineData("https://localhost/build")]
    [InlineData("https://thing.local/build")]
    [InlineData("https://127.0.0.1/build")]
    [InlineData("https://10.0.0.1/build")]
    [InlineData("https://[::1]/build")]
    [InlineData("not a URL")]
    public void RejectsNonPublicOrNonStandardUrls(string rawUrl)
    {
        Assert.Throws<PublicNetworkException>(
            () => PublicNetworkPolicy.ValidateHttpsUri(rawUrl));
    }

    [Theory]
    [InlineData("8.8.8.8", true)]
    [InlineData("93.184.216.34", true)]
    [InlineData("0.0.0.0", false)]
    [InlineData("10.10.10.10", false)]
    [InlineData("100.64.0.1", false)]
    [InlineData("127.0.0.1", false)]
    [InlineData("169.254.169.254", false)]
    [InlineData("172.16.0.1", false)]
    [InlineData("172.31.255.255", false)]
    [InlineData("192.168.1.1", false)]
    [InlineData("192.0.2.1", false)]
    [InlineData("198.18.0.1", false)]
    [InlineData("198.51.100.1", false)]
    [InlineData("203.0.113.1", false)]
    [InlineData("224.0.0.1", false)]
    [InlineData("255.255.255.255", false)]
    [InlineData("2606:4700:4700::1111", true)]
    [InlineData("::", false)]
    [InlineData("::1", false)]
    [InlineData("::ffff:127.0.0.1", false)]
    [InlineData("fc00::1", false)]
    [InlineData("fe80::1", false)]
    [InlineData("ff02::1", false)]
    [InlineData("2001:db8::1", false)]
    public void ClassifiesPublicAddresses(string address, bool expected)
    {
        Assert.Equal(expected, PublicNetworkPolicy.IsPublic(IPAddress.Parse(address)));
    }

    [Fact]
    public async Task RejectsHostWhenAnyDnsAnswerIsPrivate()
    {
        var resolver = new SequenceResolver(
            [
                IPAddress.Parse("93.184.216.34"),
                IPAddress.Parse("127.0.0.1"),
            ]);

        var exception = await Assert.ThrowsAsync<PublicNetworkException>(
            () => PublicNetworkPolicy.ResolvePublicAsync("example.com", resolver));

        Assert.Equal(PublicNetworkFailure.BlockedAddress, exception.Failure);
    }

    [Fact]
    public async Task RejectsPrivateSecondResolutionForRebinding()
    {
        var resolver = new SequenceResolver(
            [IPAddress.Parse("93.184.216.34")],
            [IPAddress.Parse("169.254.169.254")]);

        var first = await PublicNetworkPolicy.ResolvePublicAsync(
            "attacker.example",
            resolver);
        var exception = await Assert.ThrowsAsync<PublicNetworkException>(
            () => PublicNetworkPolicy.ResolvePublicAsync(
                "attacker.example",
                resolver));

        Assert.Single(first);
        Assert.Equal(PublicNetworkFailure.BlockedAddress, exception.Failure);
    }

    private sealed class SequenceResolver(params IPAddress[][] answers)
        : IHostAddressResolver
    {
        private int index;

        public Task<IPAddress[]> ResolveAsync(
            string host,
            CancellationToken cancellationToken = default)
        {
            _ = host;
            cancellationToken.ThrowIfCancellationRequested();
            var answer = answers[Math.Min(index, answers.Length - 1)];
            index++;
            return Task.FromResult(answer);
        }
    }
}
