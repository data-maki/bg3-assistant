using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;

namespace BG3HonorAssistant.Core.Tests.Serialization;

public sealed class HonorRunSerializationTests
{
    [Fact]
    public void DecodesLegacyMacSnapshotAndNormalizesNewFields()
    {
        const string snapshot =
            """
            {
              "id": "mac-run",
              "name": "Mac Run",
              "createdAt": 0,
              "guideVersion": "guide-v1",
              "party": [
                {
                  "id": "tav",
                  "name": "Tav",
                  "level": 4,
                  "preparedTags": [],
                  "className": "Fighter"
                }
              ],
              "progress": {},
              "mapRegion": "Wilderness"
            }
            """;

        var run = Assert.IsType<HonorRun>(
            JsonSerializer.Deserialize<HonorRun>(
                snapshot,
                JsonDefaults.Create()));
        run.NormalizeRoster();

        Assert.Equal("mac-run", run.Id);
        Assert.Equal(
            new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero),
            run.CreatedAt);
        Assert.Equal(12, run.Roster!.Count);
        Assert.False(run.IncludeCampPlans);
        Assert.False(run.EquipmentOwnershipKnown);
    }

    [Fact]
    public void RoundTripUsesMacFieldAndDateShapeWithoutComputedProperties()
    {
        var run = new HonorRun
        {
            Id = "run",
            Name = "Run",
            CreatedAt =
                new DateTimeOffset(2001, 1, 2, 0, 0, 0, TimeSpan.Zero),
        };
        run.NormalizeRoster();
        run.Progress["fight"] = new CheckpointProgress
        {
            CheckedPreparation = ["Potion"],
            SkipNote = "Reason",
            UpdatedAt =
                new DateTimeOffset(2001, 1, 3, 0, 0, 0, TimeSpan.Zero),
        };

        var json = JsonSerializer.Serialize(run, JsonDefaults.Create());
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        Assert.Equal(86400, root.GetProperty("createdAt").GetDouble());
        Assert.Equal(
            172800,
            root.GetProperty("progress")
                .GetProperty("fight")
                .GetProperty("updatedAt")
                .GetDouble());
        var tav = root.GetProperty("party")[0];
        Assert.False(tav.TryGetProperty("rosterStatus", out _));
        Assert.False(tav.TryGetProperty("effectiveAbilityScores", out _));
        Assert.False(
            tav.GetProperty("abilityScores")
                .TryGetProperty("clampedForPointBuy", out _));

        var roundTrip = Assert.IsType<HonorRun>(
            JsonSerializer.Deserialize<HonorRun>(
                json,
                JsonDefaults.Create()));
        Assert.Equal(run.Id, roundTrip.Id);
        Assert.Equal(run.CreatedAt, roundTrip.CreatedAt);
        Assert.Equal(
            run.Progress["fight"].UpdatedAt,
            roundTrip.Progress["fight"].UpdatedAt);
    }
}
