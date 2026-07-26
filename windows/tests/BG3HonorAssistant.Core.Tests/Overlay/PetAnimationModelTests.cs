using BG3HonorAssistant.Core.Overlay;

namespace BG3HonorAssistant.Core.Tests.Overlay;

public sealed class PetAnimationModelTests
{
    private static readonly PetSize View = new(84, 90.72);

    [Fact]
    public void RestingFrameIsStableWhenNotHovered()
    {
        Assert.Equal(
            new PetSpriteFrame(0, 0),
            PetAnimationModel.Frame(
                false,
                TimeSpan.FromHours(4),
                new PetPoint(1000, 1000),
                View,
                reduceMotion: false));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(139, 0)]
    [InlineData(140, 1)]
    [InlineData(279, 1)]
    [InlineData(560, 4)]
    [InlineData(839, 4)]
    public void HoverIntroUsesAuthoredJumpTiming(int milliseconds, int column)
    {
        Assert.Equal(
            new PetSpriteFrame(4, column),
            PetAnimationModel.Frame(
                true,
                TimeSpan.FromMilliseconds(milliseconds),
                pointerLocation: null,
                View,
                reduceMotion: false));
    }

    [Theory]
    [InlineData(840, 0)]
    [InlineData(1119, 0)]
    [InlineData(1120, 1)]
    [InlineData(1230, 2)]
    public void IdleLoopBeginsAfterJumpIntro(int milliseconds, int column)
    {
        Assert.Equal(
            new PetSpriteFrame(0, column),
            PetAnimationModel.Frame(
                true,
                TimeSpan.FromMilliseconds(milliseconds),
                pointerLocation: null,
                View,
                reduceMotion: false));
    }

    [Theory]
    [InlineData(42, 0, 9, 0)]
    [InlineData(84, 45.36, 9, 4)]
    [InlineData(42, 90.72, 10, 0)]
    [InlineData(0, 45.36, 10, 4)]
    public void PointerDirectionMatchesSixteenDirectionAtlas(
        double x,
        double y,
        int row,
        int column)
    {
        Assert.Equal(
            new PetSpriteFrame(row, column),
            PetAnimationModel.Frame(
                true,
                PetAnimationModel.HoverIntroDuration,
                new PetPoint(x, y),
                View,
                reduceMotion: false));
    }

    [Fact]
    public void ReducedMotionSkipsJumpAndIdleButKeepsIntentionalLook()
    {
        Assert.Equal(
            new PetSpriteFrame(0, 0),
            PetAnimationModel.Frame(
                true,
                TimeSpan.Zero,
                new PetPoint(View.Width / 2D, View.Height / 2D),
                View,
                reduceMotion: true));
        Assert.Equal(
            new PetSpriteFrame(9, 4),
            PetAnimationModel.Frame(
                true,
                TimeSpan.Zero,
                new PetPoint(View.Width, View.Height / 2D),
                View,
                reduceMotion: true));
    }
}
