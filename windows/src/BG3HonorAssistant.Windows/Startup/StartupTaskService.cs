using BG3HonorAssistant.Windows.Packaging;
using Windows.ApplicationModel;

namespace BG3HonorAssistant.Windows.Startup;

public enum StartupRegistrationState
{
    Unavailable,
    Disabled,
    Enabled,
    DisabledByUser,
    DisabledByPolicy,
    EnabledByPolicy,
}

public sealed record StartupRegistrationStatus(
    StartupRegistrationState State,
    string Message)
{
    public bool CanRequestEnable => State == StartupRegistrationState.Disabled;
}

public sealed class StartupTaskService
{
    public const string TaskId = "BG3HonorAssistantStartup";

    public async Task<StartupRegistrationStatus> GetStatusAsync()
    {
        if (!PackageIdentity.IsPackaged)
        {
            return Unavailable();
        }

        var task = await StartupTask.GetAsync(TaskId);
        return Map(task.State);
    }

    public async Task<StartupRegistrationStatus> RequestEnableFromUserActionAsync()
    {
        if (!PackageIdentity.IsPackaged)
        {
            return Unavailable();
        }

        var task = await StartupTask.GetAsync(TaskId);
        if (task.State == StartupTaskState.Disabled)
        {
            _ = await task.RequestEnableAsync();
        }

        return Map(task.State);
    }

    public async Task<StartupRegistrationStatus> DisableFromUserActionAsync()
    {
        if (!PackageIdentity.IsPackaged)
        {
            return Unavailable();
        }

        var task = await StartupTask.GetAsync(TaskId);
        if (task.State == StartupTaskState.Enabled)
        {
            task.Disable();
        }

        return Map(task.State);
    }

    private static StartupRegistrationStatus Map(StartupTaskState state)
    {
        return state switch
        {
            StartupTaskState.Disabled => new(
                StartupRegistrationState.Disabled,
                "Start at login is off."),
            StartupTaskState.Enabled => new(
                StartupRegistrationState.Enabled,
                "Start at login is on."),
            StartupTaskState.DisabledByUser => new(
                StartupRegistrationState.DisabledByUser,
                "Windows disabled this startup task. Re-enable it in Settings > Apps > Startup."),
            StartupTaskState.DisabledByPolicy => new(
                StartupRegistrationState.DisabledByPolicy,
                "Startup is disabled by Windows policy."),
            StartupTaskState.EnabledByPolicy => new(
                StartupRegistrationState.EnabledByPolicy,
                "Startup is enabled by Windows policy."),
            _ => new(
                StartupRegistrationState.Unavailable,
                $"Unknown Windows startup state: {state}."),
        };
    }

    private static StartupRegistrationStatus Unavailable()
    {
        return new StartupRegistrationStatus(
            StartupRegistrationState.Unavailable,
            "Start at login is available only from the installed MSIX.");
    }
}
