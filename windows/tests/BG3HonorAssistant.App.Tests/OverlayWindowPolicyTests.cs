using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.App.Tests;

public sealed class OverlayWindowPolicyTests
{
    [Theory]
    [InlineData(OverlayDensity.Minimal, false)]
    [InlineData(OverlayDensity.Focus, true)]
    [InlineData(OverlayDensity.Reference, true)]
    public void NonMinimalDensitiesUseTheFocusCard(
        OverlayDensity density,
        bool expected)
    {
        Assert.Equal(expected, OverlayWindow.ShowsFocusPanel(density));
    }
}
