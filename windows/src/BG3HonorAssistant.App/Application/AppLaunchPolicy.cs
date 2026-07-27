using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.App;

internal static class AppLaunchPolicy
{
    public static bool ShouldShowPlanner(AppPreferences preferences)
    {
        ArgumentNullException.ThrowIfNull(preferences);
        return preferences.OnboardingVersion < OnboardingFlow.Version;
    }
}
