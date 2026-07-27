using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.App.Tests;

public sealed class AppLaunchPolicyTests
{
    [Fact]
    public void FirstLaunchShowsOnboardingAndCompletedOnboardingStartsInTray()
    {
        Assert.True(AppLaunchPolicy.ShouldShowPlanner(new AppPreferences()));
        Assert.False(
            AppLaunchPolicy.ShouldShowPlanner(
                new AppPreferences
                {
                    OnboardingVersion = OnboardingFlow.Version,
                }));
    }
}
