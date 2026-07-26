using System.Xml.Linq;

namespace BG3HonorAssistant.Package.Tests;

public sealed class PackageManifestTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string ManifestPath = Path.Combine(
        RepositoryRoot,
        "windows",
        "package",
        "Package.appxmanifest");
    private static readonly string ExecutableManifestPath = Path.Combine(
        RepositoryRoot,
        "windows",
        "src",
        "BG3HonorAssistant.App",
        "app.manifest");

    [Fact]
    public void ManifestTargetsOnlySupportedWindowsDesktopArchitecture()
    {
        var document = XDocument.Load(ManifestPath);
        XNamespace foundation = "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
        XNamespace uap10 = "http://schemas.microsoft.com/appx/manifest/uap/windows10/10";

        var identity = Assert.Single(document.Descendants(foundation + "Identity"));
        Assert.Equal("x64", identity.Attribute("ProcessorArchitecture")?.Value);

        var target = Assert.Single(document.Descendants(foundation + "TargetDeviceFamily"));
        Assert.Equal("Windows.Desktop", target.Attribute("Name")?.Value);
        Assert.Equal("10.0.26100.0", target.Attribute("MinVersion")?.Value);

        var application = Assert.Single(document.Descendants(foundation + "Application"));
        Assert.Equal("BG3HonorAssistant.exe", application.Attribute("Executable")?.Value);
        Assert.Equal("Windows.FullTrustApplication", application.Attribute("EntryPoint")?.Value);
        Assert.Equal("packagedClassicApp", application.Attribute(uap10 + "RuntimeBehavior")?.Value);
        Assert.Equal("mediumIL", application.Attribute(uap10 + "TrustLevel")?.Value);
    }

    [Fact]
    public void ManifestDeclaresOnlyReviewedCapabilities()
    {
        var document = XDocument.Load(ManifestPath);
        XNamespace foundation = "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
        XNamespace restricted =
            "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities";

        var capabilities = Assert.Single(document.Descendants(foundation + "Capabilities"));
        var declared = capabilities.Elements()
            .Select(element => (
                element.Name.NamespaceName,
                Name: element.Attribute("Name")?.Value))
            .ToArray();

        Assert.Equal(
            [
                (restricted.NamespaceName, "runFullTrust")
            ],
            declared);
    }

    [Fact]
    public void StartupTaskIsPackagedButDisabledByDefault()
    {
        var document = XDocument.Load(ManifestPath);
        XNamespace desktop = "http://schemas.microsoft.com/appx/manifest/desktop/windows10";

        var startupTask = Assert.Single(document.Descendants(desktop + "StartupTask"));
        Assert.Equal("false", startupTask.Attribute("Enabled")?.Value);
    }

    [Fact]
    public void MvpExcludesCaptureAndMicrophoneProductSurface()
    {
        var appXaml = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App",
            "MainWindow.xaml"));
        var solution = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "BG3HonorAssistant.slnx"));

        Assert.DoesNotContain("StartSpeech", appXaml, StringComparison.Ordinal);
        Assert.DoesNotContain("microphone", appXaml, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("CaptureHarness", solution, StringComparison.Ordinal);
        Assert.Empty(EnumerateProductFiles("Capture"));
        Assert.Empty(EnumerateProductFiles("Speech"));
    }

    [Fact]
    public void TypedNetworkSurfaceUsesOneTextOnlyClientAndNoSqliteCredentialPath()
    {
        var sourceRoot = Path.Combine(RepositoryRoot, "windows", "src");
        var productSources = Directory
            .EnumerateFiles(sourceRoot, "*.*", SearchOption.AllDirectories)
            .Where(path => path.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
            .Select(File.ReadAllText)
            .ToList();
        var appXaml = File.ReadAllText(Path.Combine(
            sourceRoot,
            "BG3HonorAssistant.App",
            "MainWindow.xaml"));
        var persistence = File.ReadAllText(Path.Combine(
            sourceRoot,
            "BG3HonorAssistant.Infrastructure",
            "Persistence",
            "RunRepository.cs"));

        Assert.Single(
            productSources.SelectMany(
                source => Occurrences(source, "new HttpClient(")));
        Assert.Contains(
            "OpenRouterKeyPasswordBox",
            appXaml,
            StringComparison.Ordinal);
        Assert.Contains(
            "ChatDraftTextBox",
            appXaml,
            StringComparison.Ordinal);
        Assert.Contains(
            "BuildImportUrlTextBox",
            appXaml,
            StringComparison.Ordinal);
        Assert.DoesNotContain("screenshot", appXaml, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("clipboard", appXaml, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("microphone", appXaml, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("dictation", appXaml, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("apiKey", persistence, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("OpenRouter", persistence, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void TraySurfaceContainsEveryMacOracleCommand()
    {
        var appSource = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App",
            "TrayMenu.cs"));

        foreach (var label in new[]
                 {
                     "Show Overlay",
                     "Open Planner",
                     "Open Map",
                     "Run:",
                     "Launch Baldur's Gate 3",
                     "Hide Pet",
                     "Show Pet",
                     "Settings",
                     "Quit",
                 })
        {
            Assert.Contains(label, appSource, StringComparison.Ordinal);
        }

        Assert.Contains(
            "actions.SwitchRun",
            appSource,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "RegisterHotKey",
            appSource,
            StringComparison.Ordinal);
    }

    [Fact]
    public void ExecutableManifestForbidsElevationAndUsesPerMonitorDpi()
    {
        var executable = XDocument.Load(ExecutableManifestPath);
        XNamespace assemblyV3 = "urn:schemas-microsoft-com:asm.v3";
        XNamespace windowsSettings =
            "http://schemas.microsoft.com/SMI/2016/WindowsSettings";

        var executionLevel = Assert.Single(executable.Descendants(assemblyV3 + "requestedExecutionLevel"));
        Assert.Equal("asInvoker", executionLevel.Attribute("level")?.Value);
        Assert.Equal("false", executionLevel.Attribute("uiAccess")?.Value);
        Assert.Equal(
            "PerMonitorV2,PerMonitor",
            Assert.Single(executable.Descendants(windowsSettings + "dpiAwareness")).Value);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) &&
                Directory.Exists(Path.Combine(directory.FullName, "windows")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate the repository root.");
    }

    private static IEnumerable<string> EnumerateProductFiles(string directoryName)
    {
        var directory = Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.Windows",
            directoryName);
        return Directory.Exists(directory)
            ? Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories)
            : [];
    }

    private static IEnumerable<int> Occurrences(string value, string needle)
    {
        for (var offset = 0;
             (offset = value.IndexOf(needle, offset, StringComparison.Ordinal)) >= 0;
             offset += needle.Length)
        {
            yield return offset;
        }
    }
}
