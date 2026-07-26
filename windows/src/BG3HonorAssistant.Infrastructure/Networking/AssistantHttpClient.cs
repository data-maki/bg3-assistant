using System.IO.Compression;
using System.Net;
using System.Net.Sockets;

namespace BG3HonorAssistant.Infrastructure.Networking;

public static class AssistantHttpClient
{
    private static readonly Lazy<HttpClient> Shared = new(Create);

    public static HttpClient Instance => Shared.Value;

    private static HttpClient Create()
    {
        var resolver = new SystemHostAddressResolver();
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            AutomaticDecompression =
                DecompressionMethods.Brotli |
                DecompressionMethods.Deflate |
                DecompressionMethods.GZip,
            ConnectTimeout = TimeSpan.FromSeconds(15),
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            PooledConnectionIdleTimeout = TimeSpan.FromMinutes(2),
            UseCookies = false,
        };
        handler.ConnectCallback = async (context, cancellationToken) =>
        {
            var endpoint = context.DnsEndPoint;
            var addresses = await PublicNetworkPolicy.ResolvePublicAsync(
                    endpoint.Host,
                    resolver,
                    cancellationToken)
                .ConfigureAwait(false);
            var socket = new Socket(SocketType.Stream, ProtocolType.Tcp)
            {
                NoDelay = true,
            };
            try
            {
                await socket.ConnectAsync(
                        addresses,
                        endpoint.Port,
                        cancellationToken)
                    .ConfigureAwait(false);
                return new NetworkStream(socket, ownsSocket: true);
            }
            catch
            {
                socket.Dispose();
                throw;
            }
        };

        return new HttpClient(handler, disposeHandler: true)
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
    }
}
