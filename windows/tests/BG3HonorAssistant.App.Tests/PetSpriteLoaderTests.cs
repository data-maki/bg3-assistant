using BG3HonorAssistant.Core.Overlay;

namespace BG3HonorAssistant.App.Tests;

public sealed class PetSpriteLoaderTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(4, 4)]
    [InlineData(10, 7)]
    public void BundledWindowsCodecDecodesAndCropsAtlasFrame(int row, int column)
    {
        var frame = PetSpriteLoader.Frame(new PetSpriteFrame(row, column));

        Assert.NotNull(frame);
        Assert.Equal(192, frame.PixelWidth);
        Assert.Equal(208, frame.PixelHeight);
    }

    [Theory]
    [InlineData(-1, 0)]
    [InlineData(11, 0)]
    [InlineData(0, -1)]
    [InlineData(0, 8)]
    public void InvalidAtlasCoordinatesReturnNoFrame(int row, int column)
    {
        Assert.Null(PetSpriteLoader.Frame(new PetSpriteFrame(row, column)));
    }
}
