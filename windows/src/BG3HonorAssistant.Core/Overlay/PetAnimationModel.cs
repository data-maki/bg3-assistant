namespace BG3HonorAssistant.Core.Overlay;

public readonly record struct PetSpriteFrame(int Row, int Column);

public readonly record struct PetPoint(double X, double Y);

public readonly record struct PetSize(double Width, double Height);

public static class PetAnimationModel
{
    public static readonly IReadOnlyList<int> IdleDurations =
        [280, 110, 110, 140, 140, 320];

    public static readonly IReadOnlyList<int> JumpingDurations =
        [140, 140, 140, 140, 280];

    public static TimeSpan HoverIntroDuration =>
        TimeSpan.FromMilliseconds(JumpingDurations.Sum());

    public static PetSpriteFrame Frame(
        bool isHovered,
        TimeSpan hoverElapsed,
        PetPoint? pointerLocation,
        PetSize viewSize,
        bool reduceMotion)
    {
        if (!isHovered)
        {
            return new PetSpriteFrame(0, 0);
        }

        if (!reduceMotion && hoverElapsed < HoverIntroDuration)
        {
            return new PetSpriteFrame(
                4,
                AnimationColumn(hoverElapsed, JumpingDurations));
        }

        if (pointerLocation is { } pointer &&
            LookFrame(pointer, viewSize) is { } look)
        {
            return look;
        }

        if (reduceMotion)
        {
            return new PetSpriteFrame(0, 0);
        }

        return new PetSpriteFrame(
            0,
            AnimationColumn(
                hoverElapsed - HoverIntroDuration < TimeSpan.Zero
                    ? TimeSpan.Zero
                    : hoverElapsed - HoverIntroDuration,
                IdleDurations));
    }

    public static PetSpriteFrame? LookFrame(
        PetPoint pointerLocation,
        PetSize viewSize)
    {
        var centerX = viewSize.Width / 2D;
        var centerY = viewSize.Height / 2D;
        var dx = pointerLocation.X - centerX;
        var dy = pointerLocation.Y - centerY;
        var deadzone = Math.Min(viewSize.Width, viewSize.Height) * 0.14D;
        if (Math.Sqrt((dx * dx) + (dy * dy)) <= deadzone)
        {
            return null;
        }

        var degrees = Math.Atan2(dx, -dy) * 180D / Math.PI;
        if (degrees < 0D)
        {
            degrees += 360D;
        }

        var direction = (int)Math.Floor((degrees + 11.25D) / 22.5D) % 16;
        return new PetSpriteFrame(
            direction < 8 ? 9 : 10,
            direction % 8);
    }

    private static int AnimationColumn(
        TimeSpan elapsed,
        IReadOnlyList<int> durations)
    {
        var total = durations.Sum();
        if (total <= 0)
        {
            return 0;
        }

        var remaining = (int)Math.Max(0D, elapsed.TotalMilliseconds) % total;
        for (var column = 0; column < durations.Count; column++)
        {
            if (remaining < durations[column])
            {
                return column;
            }

            remaining -= durations[column];
        }

        return Math.Max(0, durations.Count - 1);
    }
}
