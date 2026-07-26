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
    public void ManifestTemplateRequiresExplicitSupportedWindowsDesktopArchitecture()
    {
        var document = XDocument.Load(ManifestPath);
        XNamespace foundation = "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
        XNamespace uap10 = "http://schemas.microsoft.com/appx/manifest/uap/windows10/10";

        var identity = Assert.Single(document.Descendants(foundation + "Identity"));
        Assert.Equal(
            "ARCHITECTURE_PLACEHOLDER",
            identity.Attribute("ProcessorArchitecture")?.Value);
        Assert.DoesNotContain(
            identity.Attributes(),
            attribute =>
                attribute.Value.Equals("neutral", StringComparison.OrdinalIgnoreCase) ||
                attribute.Value.Equals("AnyCPU", StringComparison.OrdinalIgnoreCase) ||
                attribute.Value.Equals("MSIL", StringComparison.OrdinalIgnoreCase));

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
    public void DevelopmentMsixBuildValidatesBothArchitectureSpecificPackages()
    {
        var script = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "tools",
            "build-development-msix.ps1"));
        var validator = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "package",
            "validate-package-architecture.ps1"));

        Assert.Contains(
            "[ValidateSet('arm64', 'x64')]",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "$runtimeIdentifier = \"win-$Architecture\"",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "-Architecture $Architecture",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "ProcessorArchitecture = $Architecture",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "-Root $publishRoot",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "MakeAppx validation unpack failed",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "-Root $inspectionRoot",
            script,
            StringComparison.Ordinal);
        Assert.Contains(
            "ARM64EC payloads are not allowed",
            validator,
            StringComparison.Ordinal);
        Assert.Contains(
            "Cross-architecture PE payload",
            validator,
            StringComparison.Ordinal);
        Assert.Contains(
            "IsArchitectureNeutralIl",
            validator,
            StringComparison.Ordinal);
        Assert.Contains(
            "exactly one Application",
            validator,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "ProcessorArchitecture=\"x64\"",
            script,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            "\\x64\\makeappx.exe$",
            script,
            StringComparison.OrdinalIgnoreCase);
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
        var appXaml = ReadAppXaml();
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
        var appXaml = ReadAppXaml();
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
            "Shell",
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
            if (File.Exists(Path.Combine(
                    directory.FullName,
                    "windows",
                    "BG3HonorAssistant.slnx")) &&
                Directory.Exists(Path.Combine(directory.FullName, "Resources")))
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

    private static string ReadAppXaml()
    {
        var appRoot = Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App");
        return string.Join(
            Environment.NewLine,
            Directory
                .EnumerateFiles(appRoot, "*.xaml", SearchOption.AllDirectories)
                .OrderBy(path => path, StringComparer.Ordinal)
                .Select(File.ReadAllText));
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
