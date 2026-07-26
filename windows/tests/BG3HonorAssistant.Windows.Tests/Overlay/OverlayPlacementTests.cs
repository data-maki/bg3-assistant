using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Overlay;

namespace BG3HonorAssistant.Windows.Tests.Overlay;

public sealed class OverlayPlacementTests
{
    [Theory]
    [InlineData(96, 380, 250)]
    [InlineData(144, 570, 375)]
    [InlineData(192, 760, 500)]
    public void ConvertsDipsAtSupportedDisplayScales(
        uint dpi,
        int expectedWidth,
        int expectedHeight)
    {
        Assert.Equal(
            expectedWidth,
            OverlayDpiCalculator.ToPhysicalPixels(380, dpi));
        Assert.Equal(
            expectedHeight,
            OverlayDpiCalculator.ToPhysicalPixels(250, dpi));
    }

    [Fact]
    public void PlacesOverlayInsideRightSideOfGameWindow()
    {
        var bounds = new WindowBounds(100, 50, 2020, 1130);

        var placement = OverlayPlacementCalculator.AtRightEdge(bounds, 380, 250);

        Assert.Equal(1622, placement.X);
        Assert.Equal(374, placement.Y);
        Assert.Equal(380, placement.Width);
        Assert.Equal(250, placement.Height);
    }

    [Fact]
    public void HandlesNegativeMonitorCoordinates()
    {
        var bounds = new WindowBounds(-2560, -200, -640, 880);

        var placement = OverlayPlacementCalculator.AtRightEdge(bounds, 380, 250);

        Assert.InRange(placement.X, bounds.Left, bounds.Right - placement.Width);
        Assert.InRange(placement.Y, bounds.Top, bounds.Bottom - placement.Height);
    }

    [Fact]
    public void ClampsOversizedOverlayToGameBounds()
    {
        var bounds = new WindowBounds(20, 40, 320, 240);

        var placement = OverlayPlacementCalculator.AtRightEdge(bounds, 800, 600);

        Assert.Equal(new OverlayPlacement(20, 40, 300, 200), placement);
    }

    [Fact]
    public void RejectsEmptyGameBounds()
    {
        Assert.Throws<ArgumentException>(() =>
            OverlayPlacementCalculator.AtRightEdge(default, 380, 250));
    }

    [Fact]
    public void NormalizedAnchorRoundTripsAcrossNegativeMonitorCoordinates()
    {
        var bounds = new WindowBounds(-2560, -300, -640, 780);
        var original = new OverlayAnchor(0.25, 0.75);

        var placement = OverlayPlacementCalculator.AtNormalizedAnchor(
            bounds,
            380,
            250,
            original);
        var normalized = OverlayPlacementCalculator.Normalize(bounds, placement);

        Assert.Equal(original.X, normalized.X, precision: 2);
        Assert.Equal(original.Y, normalized.Y, precision: 2);
        Assert.InRange(placement.X, bounds.Left, bounds.Right - placement.Width);
        Assert.InRange(placement.Y, bounds.Top, bounds.Bottom - placement.Height);
    }

    [Theory]
    [InlineData(-1, 2, 0, 1)]
    [InlineData(2, -1, 1, 0)]
    public void NormalizedAnchorClampsToReference(
        double x,
        double y,
        double expectedX,
        double expectedY)
    {
        var bounds = new WindowBounds(100, 50, 2020, 1130);

        var placement = OverlayPlacementCalculator.AtNormalizedAnchor(
            bounds,
            380,
            250,
            new OverlayAnchor(x, y));
        var normalized = OverlayPlacementCalculator.Normalize(bounds, placement);

        Assert.Equal(expectedX, normalized.X, precision: 3);
        Assert.Equal(expectedY, normalized.Y, precision: 3);
    }
}
