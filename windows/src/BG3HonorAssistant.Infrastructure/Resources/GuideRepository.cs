using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;

namespace BG3HonorAssistant.Infrastructure.Resources;

public sealed class GuideRepository
{
    private readonly JsonSerializerOptions serializerOptions;

    public GuideRepository(JsonSerializerOptions? serializerOptions = null)
    {
        this.serializerOptions = serializerOptions ?? JsonDefaults.Create();
    }

    public async Task<GuideBundle> LoadAsync(
        string guidePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(guidePath);
        await using var stream = File.OpenRead(guidePath);
        var guide = await JsonSerializer.DeserializeAsync<GuideBundle>(
            stream,
            serializerOptions,
            cancellationToken);
        if (guide is null)
        {
            throw new InvalidDataException("The guide bundle decoded to null.");
        }

        Validate(guide);
        return guide;
    }

    private static void Validate(GuideBundle guide)
    {
        if (string.IsNullOrWhiteSpace(guide.GuideVersion))
        {
            throw new InvalidDataException("The guide version is missing.");
        }

        foreach (var act in Enumerable.Range(1, 3))
        {
            if (!guide.Payloads.TryGetValue(act.ToString(), out var payload))
            {
                throw new InvalidDataException($"Guide payload for Act {act} is missing.");
            }

            if (payload.Act != act)
            {
                throw new InvalidDataException(
                    $"Guide payload key {act} contains Act {payload.Act}.");
            }

            if (!string.Equals(
                    payload.GuideVersion,
                    guide.GuideVersion,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    $"Act {act} guide version does not match the bundle.");
            }
        }

        var actTwo = guide.Payloads["2"];
        if (actTwo.RouteAvailable ||
            actTwo.Checkpoints.Count != 0 ||
            actTwo.Walkthrough.Count != 0 ||
            actTwo.TimedEvents.Count != 0)
        {
            throw new InvalidDataException(
                "Act 2 must remain an explicit route data gap for this guide version.");
        }
    }
}
