using BG3HonorAssistant.Windows.Shell;

namespace BG3HonorAssistant.Windows.Tests.Shell;

public sealed class GameLauncherTests
{
    [Fact]
    public void SteamLaunchUriMatchesMacOracleAppId()
    {
        Assert.Equal("steam://run/1086940", GameLauncher.SteamUri);
        var uri = new Uri(GameLauncher.SteamUri);
        Assert.Equal("steam", uri.Scheme);
        Assert.Equal("run", uri.Host);
        Assert.Equal("/1086940", uri.AbsolutePath);
    }

    [Theory]
    [InlineData("https://mapgenie.io/baldurs-gate-3/maps/wilderness", true)]
    [InlineData("http://example.test/map", true)]
    [InlineData("file:///C:/private/map.html", false)]
    [InlineData("javascript:alert(1)", false)]
    [InlineData("/relative", false)]
    public void ExternalMapAllowsOnlyAbsoluteWebLinks(
        string value,
        bool expected)
    {
        Assert.Equal(expected, GameLauncher.TryCreateHttpUri(value, out _));
    }
}
