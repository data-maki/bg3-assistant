namespace BG3HonorAssistant.Windows.Overlay;

public static class OverlayDpiCalculator
{
    private const uint DefaultDpi = 96;

    public static int ToPhysicalPixels(
        double deviceIndependentPixels,
        uint targetWindowDpi)
    {
        if (!double.IsFinite(deviceIndependentPixels))
        {
            throw new ArgumentOutOfRangeException(
                nameof(deviceIndependentPixels),
                "The device-independent size must be finite.");
        }

        var dpi = targetWindowDpi == 0 ? DefaultDpi : targetWindowDpi;
        return Math.Max(
            1,
            checked((int)Math.Round(
                deviceIndependentPixels * dpi / DefaultDpi,
                MidpointRounding.AwayFromZero)));
    }
}
