using BG3HonorAssistant.Windows.GameDetection;

namespace BG3HonorAssistant.Windows.Tests.GameDetection;

public sealed class Bg3ProcessNamesTests
{
    [Theory]
    [InlineData("bg3")]
    [InlineData("BG3.EXE")]
    [InlineData("bg3_dx11")]
    [InlineData("Bg3_Dx11.exe")]
    public void AcceptsOnlyDocumentedExecutables(string processName)
    {
        Assert.True(Bg3ProcessNames.IsSupported(processName));
    }

    [Theory]
    [InlineData("")]
    [InlineData("bg3_launcher.exe")]
    [InlineData("steam.exe")]
    [InlineData("bg3-mod.exe")]
    public void RejectsOtherProcesses(string processName)
    {
        Assert.False(Bg3ProcessNames.IsSupported(processName));
    }
}
