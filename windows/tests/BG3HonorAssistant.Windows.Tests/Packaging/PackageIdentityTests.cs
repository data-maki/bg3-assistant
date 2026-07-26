using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Startup;

namespace BG3HonorAssistant.Windows.Tests.Packaging;

public sealed class PackageIdentityTests
{
    [Fact]
    public async Task UnpackagedTestHostReportsSafeStartupFallback()
    {
        Assert.False(PackageIdentity.IsPackaged);
        Assert.Null(PackageIdentity.TryGetFullName());

        var status = await new StartupTaskService().GetStatusAsync();

        Assert.Equal(StartupRegistrationState.Unavailable, status.State);
        Assert.False(status.CanRequestEnable);
        Assert.Contains("installed MSIX", status.Message, StringComparison.Ordinal);
    }
}
