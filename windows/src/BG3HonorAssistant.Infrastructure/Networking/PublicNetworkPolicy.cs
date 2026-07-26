using System.Net;
using System.Net.Sockets;

namespace BG3HonorAssistant.Infrastructure.Networking;

public interface IHostAddressResolver
{
    Task<IPAddress[]> ResolveAsync(
        string host,
        CancellationToken cancellationToken = default);
}

public sealed class SystemHostAddressResolver : IHostAddressResolver
{
    public Task<IPAddress[]> ResolveAsync(
        string host,
        CancellationToken cancellationToken = default) =>
        Dns.GetHostAddressesAsync(host, cancellationToken);
}

public static class PublicNetworkPolicy
{
    private static readonly (uint Network, uint Mask)[] BlockedIpv4Networks =
    [
        Network4(0, 8),
        Network4(10, 8),
        Network4(100, 10, 64),
        Network4(127, 8),
        Network4(169, 16, 254),
        Network4(172, 12, 16),
        Network4(192, 24),
        Network4(192, 24, 0, 2),
        Network4(192, 24, 88, 99),
        Network4(192, 16, 168),
        Network4(198, 15, 18),
        Network4(198, 24, 51, 100),
        Network4(203, 24, 0, 113),
        Network4(224, 4),
        Network4(240, 4),
    ];

    private static readonly (byte[] Prefix, int Bits)[] BlockedIpv6Networks =
    [
        (IPAddress.IPv6None.GetAddressBytes(), 128),
        (IPAddress.IPv6Loopback.GetAddressBytes(), 128),
        (IPAddress.Parse("100::").GetAddressBytes(), 64),
        (IPAddress.Parse("2001:2::").GetAddressBytes(), 48),
        (IPAddress.Parse("2001:db8::").GetAddressBytes(), 32),
        (IPAddress.Parse("fc00::").GetAddressBytes(), 7),
        (IPAddress.Parse("fe80::").GetAddressBytes(), 10),
        (IPAddress.Parse("ff00::").GetAddressBytes(), 8),
    ];

    public static Uri ValidateHttpsUri(string rawUri)
    {
        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri))
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.InvalidUrl,
                "Enter a complete HTTPS build URL.");
        }

        return ValidateHttpsUri(uri);
    }

    public static Uri ValidateHttpsUri(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);
        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            uri.Port != 443 ||
            string.IsNullOrWhiteSpace(uri.Host) ||
            !string.IsNullOrEmpty(uri.UserInfo))
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.InvalidUrl,
                "Build imports accept public HTTPS URLs on port 443 only.");
        }

        var host = uri.IdnHost.TrimEnd('.');
        if (host.Length == 0 ||
            string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".local", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".internal", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".home.arpa", StringComparison.OrdinalIgnoreCase))
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.BlockedAddress,
                "Local and private build sources are not allowed.");
        }

        if (IPAddress.TryParse(host, out var address) && !IsPublic(address))
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.BlockedAddress,
                "Local, private, reserved, and special-use addresses are not allowed.");
        }

        return uri;
    }

    public static async Task<IPAddress[]> ResolvePublicAsync(
        string host,
        IHostAddressResolver resolver,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(host);
        ArgumentNullException.ThrowIfNull(resolver);

        IPAddress[] addresses;
        try
        {
            addresses = IPAddress.TryParse(host, out var literal)
                ? [literal]
                : await resolver.ResolveAsync(host, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is SocketException or ArgumentException)
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.NameResolution,
                "The build source host could not be resolved.",
                exception);
        }

        if (addresses.Length == 0)
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.NameResolution,
                "The build source host did not resolve to an address.");
        }

        if (addresses.Any(address => !IsPublic(address)))
        {
            throw new PublicNetworkException(
                PublicNetworkFailure.BlockedAddress,
                "The build source resolved to a local, private, reserved, or special-use address.");
        }

        return addresses.Distinct().ToArray();
    }

    public static bool IsPublic(IPAddress address)
    {
        ArgumentNullException.ThrowIfNull(address);
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var bytes = address.GetAddressBytes();
            var value =
                (uint)bytes[0] << 24 |
                (uint)bytes[1] << 16 |
                (uint)bytes[2] << 8 |
                bytes[3];
            return BlockedIpv4Networks.All(
                network => (value & network.Mask) != network.Network);
        }

        if (address.AddressFamily != AddressFamily.InterNetworkV6 ||
            address.IsIPv6LinkLocal ||
            address.IsIPv6Multicast ||
            address.IsIPv6SiteLocal)
        {
            return false;
        }

        var value6 = address.GetAddressBytes();
        return BlockedIpv6Networks.All(
            network => !HasPrefix(value6, network.Prefix, network.Bits));
    }

    private static (uint Network, uint Mask) Network4(
        byte first,
        int bits,
        byte second = 0,
        byte third = 0)
    {
        var value =
            (uint)first << 24 |
            (uint)second << 16 |
            (uint)third << 8;
        var mask = bits == 0 ? 0U : uint.MaxValue << (32 - bits);
        return (value & mask, mask);
    }

    private static bool HasPrefix(byte[] value, byte[] prefix, int bits)
    {
        var completeBytes = bits / 8;
        for (var index = 0; index < completeBytes; index++)
        {
            if (value[index] != prefix[index])
            {
                return false;
            }
        }

        var remainingBits = bits % 8;
        if (remainingBits == 0)
        {
            return true;
        }

        var mask = (byte)(0xff << (8 - remainingBits));
        return (value[completeBytes] & mask) == (prefix[completeBytes] & mask);
    }
}

public enum PublicNetworkFailure
{
    InvalidUrl,
    BlockedAddress,
    NameResolution,
}

public sealed class PublicNetworkException : Exception
{
    public PublicNetworkException(
        PublicNetworkFailure failure,
        string message,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Failure = failure;
    }

    public PublicNetworkFailure Failure { get; }
}
