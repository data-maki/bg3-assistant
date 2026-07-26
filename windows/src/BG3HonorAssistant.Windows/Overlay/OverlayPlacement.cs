using BG3HonorAssistant.Windows.GameDetection;

namespace BG3HonorAssistant.Windows.Overlay;

public readonly record struct OverlayPlacement(int X, int Y, int Width, int Height);

public readonly record struct OverlayAnchor(double X, double Y);

public static class OverlayPlacementCalculator
{
    public static OverlayPlacement AtRightEdge(
        WindowBounds gameBounds,
        int overlayWidth,
        int overlayHeight,
        int margin = 18)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(overlayWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(overlayHeight);

        if (!gameBounds.IsUsable)
        {
            throw new ArgumentException("Game bounds must have a positive area.", nameof(gameBounds));
        }

        var width = Math.Min(overlayWidth, gameBounds.Width);
        var height = Math.Min(overlayHeight, gameBounds.Height);
        var maximumX = gameBounds.Right - width;
        var maximumY = gameBounds.Bottom - height;
        var preferredX = gameBounds.Right - width - margin;
        var preferredY = gameBounds.Top + (int)Math.Round(gameBounds.Height * 0.30);

        return new OverlayPlacement(
            Math.Clamp(preferredX, gameBounds.Left, maximumX),
            Math.Clamp(preferredY, gameBounds.Top, maximumY),
            width,
            height);
    }

    public static OverlayPlacement AtNormalizedAnchor(
        WindowBounds reference,
        int overlayWidth,
        int overlayHeight,
        OverlayAnchor anchor)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(overlayWidth);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(overlayHeight);
        if (!reference.IsUsable)
        {
            throw new ArgumentException(
                "Reference bounds must have a positive area.",
                nameof(reference));
        }

        var width = Math.Min(overlayWidth, reference.Width);
        var height = Math.Min(overlayHeight, reference.Height);
        var freeWidth = Math.Max(0, reference.Width - width);
        var freeHeight = Math.Max(0, reference.Height - height);
        return new OverlayPlacement(
            reference.Left +
            (int)Math.Round(Math.Clamp(anchor.X, 0D, 1D) * freeWidth),
            reference.Top +
            (int)Math.Round(Math.Clamp(anchor.Y, 0D, 1D) * freeHeight),
            width,
            height);
    }

    public static OverlayAnchor Normalize(
        WindowBounds reference,
        OverlayPlacement placement)
    {
        if (!reference.IsUsable)
        {
            throw new ArgumentException(
                "Reference bounds must have a positive area.",
                nameof(reference));
        }

        var width = Math.Min(Math.Max(1, placement.Width), reference.Width);
        var height = Math.Min(Math.Max(1, placement.Height), reference.Height);
        var freeWidth = Math.Max(1, reference.Width - width);
        var freeHeight = Math.Max(1, reference.Height - height);
        return new OverlayAnchor(
            Math.Clamp(
                (placement.X - reference.Left) / (double)freeWidth,
                0D,
                1D),
            Math.Clamp(
                (placement.Y - reference.Top) / (double)freeHeight,
                0D,
                1D));
    }
}
