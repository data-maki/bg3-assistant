using System.Text.Json;

namespace BG3HonorAssistant.Package.Tests;

public sealed class SharedResourceTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string ResourceRoot = Path.Combine(
        RepositoryRoot,
        "Resources");

    [Fact]
    public void SharedMediaInventoryMatchesAuditedCounts()
    {
        Assert.Equal(11, CountFiles("CompanionPortraits"));
        Assert.Equal(51, CountFiles("ItemIcons"));
        Assert.Equal(697, CountFiles("BuildOptionIcons"));
        Assert.True(File.Exists(Path.Combine(ResourceRoot, "twilight-cleric.webp")));
    }

    [Fact]
    public void GuideHasExpectedVersionAndExplicitActTwoDataGap()
    {
        var guidePath = Path.Combine(ResourceRoot, "Data", "guide-bundle.json");
        using var guide = JsonDocument.Parse(File.ReadAllText(guidePath));
        var root = guide.RootElement;

        Assert.Equal(
            "2026-07-18-all-act-review-v2",
            root.GetProperty("guideVersion").GetString());

        var payloads = root.GetProperty("payloads");
        Assert.Equal(3, payloads.EnumerateObject().Count());
        var actTwo = payloads.GetProperty("2");
        Assert.False(actTwo.GetProperty("routeAvailable").GetBoolean());
        Assert.Empty(actTwo.GetProperty("checkpoints").EnumerateArray());
        Assert.Empty(actTwo.GetProperty("walkthrough").EnumerateArray());
        Assert.Empty(actTwo.GetProperty("timedEvents").EnumerateArray());
    }

    private static int CountFiles(string directory)
    {
        return Directory.EnumerateFiles(
            Path.Combine(ResourceRoot, directory),
            "*",
            SearchOption.TopDirectoryOnly).Count();
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) &&
                Directory.Exists(Path.Combine(directory.FullName, "mac")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate the repository root.");
    }
}
