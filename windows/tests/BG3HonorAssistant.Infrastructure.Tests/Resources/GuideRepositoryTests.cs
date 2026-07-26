using BG3HonorAssistant.Infrastructure.Resources;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Serialization;
using System.Text.Json;

namespace BG3HonorAssistant.Infrastructure.Tests.Resources;

public sealed class GuideRepositoryTests
{
    [Fact]
    public async Task LoadsAuditedSharedGuideWithoutDuplicatingIt()
    {
        var guide = await new GuideRepository().LoadAsync(FindGuidePath());

        Assert.Equal("2026-07-18-all-act-review-v2", guide.GuideVersion);
        Assert.Equal(3, guide.Payloads.Count);
        Assert.True(guide.Payloads["1"].RouteAvailable);
        Assert.Equal(19, guide.Payloads["1"].Checkpoints.Count);
        Assert.Equal(60, guide.Payloads["1"].Walkthrough.Count);
        Assert.False(guide.Payloads["2"].RouteAvailable);
        Assert.Empty(guide.Payloads["2"].Checkpoints);
        Assert.Empty(guide.Payloads["2"].Walkthrough);
        Assert.Empty(guide.Payloads["2"].TimedEvents);
        Assert.True(guide.Payloads["3"].RouteAvailable);
        Assert.Equal(13, guide.Payloads["3"].Checkpoints.Count);
        Assert.Equal(19, guide.Payloads["3"].Walkthrough.Count);
        Assert.All(guide.Payloads.Values, payload => Assert.Equal(9, payload.Builds.Count));
        Assert.Equal(88, guide.Items.Count);
        Assert.Equal(14, guide.Payloads["1"].TimedEvents.Count);
        Assert.Equal(3, guide.Payloads["1"].Acts.Count);
        Assert.Equal(
            "Mountain Pass point of no return",
            guide.Payloads["1"].TimedEvents[0].Name);
        Assert.Equal("Amulet of Misty Step", guide.Items[0].Name);
        Assert.Equal(386, guide.Items[0].GameX);
        Assert.IsType<ActMapHandoff.Local>(
            guide.Payloads["1"].Acts.Single(act => act.Act == 1).MapHandoff);

        var firstStep = guide.Payloads["1"].Walkthrough[0];
        Assert.Equal(
            "How hard should you commit to Commander Zhalk?",
            firstStep.Decision?.Prompt);
        Assert.Contains("Command: Drop", firstStep.Incident?.SafeActions[0]);
        Assert.Contains("Everburn Blade", firstStep.RiskReward?.Reward);
        Assert.Equal(
            23,
            guide.Payloads["1"].Checkpoints.Sum(
                checkpoint => checkpoint.HonorDecisions.Count));
    }

    [Fact]
    public async Task SharedGuideRoundTripsWithoutDroppingTypedOracleData()
    {
        var options = JsonDefaults.Create();
        var guide = await new GuideRepository(options).LoadAsync(FindGuidePath());

        var json = JsonSerializer.Serialize(guide, options);
        var roundTrip = Assert.IsType<GuideBundle>(
            JsonSerializer.Deserialize<GuideBundle>(json, options));

        Assert.Equal(guide.GuideVersion, roundTrip.GuideVersion);
        Assert.Equal(guide.Items.Count, roundTrip.Items.Count);
        Assert.Equal(
            guide.Payloads["1"].TimedEvents.Count,
            roundTrip.Payloads["1"].TimedEvents.Count);
        Assert.Equal(
            guide.Payloads["1"].Walkthrough.Count(
                step => step.Decision is not null),
            roundTrip.Payloads["1"].Walkthrough.Count(
                step => step.Decision is not null));
        var expectedIncident = Assert.IsType<IncidentProtocol>(
            guide.Payloads["1"].Walkthrough[0].Incident);
        var actualIncident = Assert.IsType<IncidentProtocol>(
            roundTrip.Payloads["1"].Walkthrough[0].Incident);
        Assert.Equal(expectedIncident.Trigger, actualIncident.Trigger);
        Assert.Equal(expectedIncident.SafeActions, actualIncident.SafeActions);
        Assert.Equal(expectedIncident.PostFight, actualIncident.PostFight);
        Assert.Equal(expectedIncident.SourceUrl, actualIncident.SourceUrl);
        Assert.Equal(
            guide.Payloads["1"].Checkpoints[0].HonorDecisions.ToArray(),
            roundTrip.Payloads["1"].Checkpoints[0].HonorDecisions.ToArray());
    }

    private static string FindGuidePath()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "mac",
                "BG3Assistant",
                "Resources",
                "Data",
                "guide-bundle.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException("Could not locate the shared guide bundle.");
    }
}
