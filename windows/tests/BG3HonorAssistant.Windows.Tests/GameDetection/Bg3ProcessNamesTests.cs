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
    [InlineData("bg3.exe")]
    [InlineData("BG3.EXE")]
    [InlineData("bg3_dx11.exe")]
    [InlineData("Bg3_Dx11.ExE")]
    public void AcceptsOnlyExactExecutableFileNames(string executableFileName)
    {
        Assert.True(
            Bg3ProcessNames.IsSupportedExecutableFileName(executableFileName));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" bg3.exe")]
    [InlineData("bg3.exe ")]
    [InlineData(@"C:\Games\Baldurs Gate 3\bin\bg3.exe")]
    [InlineData(@"C:\Games\Baldurs Gate 3\bin\bg3_dx11.exe")]
    [InlineData("bg3_launcher.exe")]
    [InlineData("bg3.exe.exe")]
    [InlineData("steam.exe")]
    [InlineData("bg3-mod.exe")]
    public void RejectsOtherProcesses(string processName)
    {
        Assert.False(Bg3ProcessNames.IsSupported(processName));
    }

    [Theory]
    [InlineData("bg3")]
    [InlineData("bg3.exe.exe")]
    [InlineData("bg3.scr")]
    [InlineData("bg3_dx11.com")]
    [InlineData("bg3_backup.exe")]
    [InlineData(@"C:\Games\Baldurs Gate 3\bin\bg3.exe")]
    public void RejectsNonExactExecutableFileNames(string executableFileName)
    {
        Assert.False(
            Bg3ProcessNames.IsSupportedExecutableFileName(executableFileName));
    }
}
