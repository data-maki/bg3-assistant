using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Startup;
using System.IO;

namespace BG3HonorAssistant.Windows.Tests.Packaging;

public sealed class PackageIdentityTests
{
    [Fact]
    public async Task UnpackagedTestHostReportsSafeStartupFallback()
    {
        Assert.False(PackageIdentity.IsPackaged);
        Assert.Null(PackageIdentity.TryGetFullName());
        Assert.Null(PackageIdentity.TryGetFamilyName());

        var status = await new StartupTaskService().GetStatusAsync();

        Assert.Equal(StartupRegistrationState.Unavailable, status.State);
        Assert.False(status.CanRequestEnable);
        Assert.Contains("installed MSIX", status.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ResolvesUnpackagedAndPackagedStateWithoutRepositoryPaths()
    {
        const string local = @"C:\Users\Player\AppData\Local";

        var unpackaged = AppDataPaths.Resolve(local, packageFamilyName: null);
        var packaged = AppDataPaths.Resolve(local, "BG3HonorAssistant_abc123");

        Assert.Equal(
            Path.Combine(local, "BG3HonorAssistant"),
            unpackaged.Root);
        Assert.Equal(
            Path.Combine(
                local,
                "Packages",
                "BG3HonorAssistant_abc123",
                "LocalState"),
            packaged.Root);
        Assert.Equal(Path.Combine(packaged.Root, "assistant.sqlite3"), packaged.Database);
    }

    [Fact]
    public void AbsoluteQaOverrideIsIsolatedAndRelativeOverrideIsRejected()
    {
        const string local = @"C:\Users\Player\AppData\Local";
        var qaState = Path.Combine(
            local,
            "BG3HonorAssistant",
            AppDataPaths.QaDirectoryName,
            "Clean-001");
        var isolated = AppDataPaths.Resolve(
            local,
            "BG3HonorAssistant_abc123",
            qaState);

        Assert.Equal(qaState, isolated.Root);
        Assert.Throws<InvalidOperationException>(
            () => AppDataPaths.Resolve(
                local,
                packageFamilyName: null,
                stateDirectoryOverride: @"relative\state"));
    }

    [Theory]
    [InlineData(@"C:\")]
    [InlineData(@"\\server\share\BG3-QA\Clean-001")]
    [InlineData(@"\\?\C:\BG3-QA\Clean-001")]
    [InlineData(@"D:\BG3-QA\Clean-001")]
    [InlineData(@"C:\Users\Player\AppData\Local\BG3HonorAssistant\QA")]
    public void QaOverrideRejectsRootsRemoteDeviceAndNonDedicatedPaths(string overridePath)
    {
        Assert.Throws<InvalidOperationException>(
            () => AppDataPaths.Resolve(
                @"C:\Users\Player\AppData\Local",
                packageFamilyName: null,
                stateDirectoryOverride: overridePath));
    }
}
