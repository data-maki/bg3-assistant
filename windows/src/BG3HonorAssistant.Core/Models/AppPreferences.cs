namespace BG3HonorAssistant.Core.Models;

public enum OverlayDensity
{
    Minimal,
    Focus,
    Reference,
}

public sealed record AppPreferences
{
    public int OnboardingVersion { get; init; }

    public OverlayDensity OverlayDensity { get; init; } = OverlayDensity.Focus;

    public bool ShowOverlayWhileGameRuns { get; init; } = true;

    public bool ReducedMotion { get; init; }

    public double? OverlayAnchorX { get; init; }

    public double? OverlayAnchorY { get; init; }
}
