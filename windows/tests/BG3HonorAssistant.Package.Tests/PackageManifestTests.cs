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
            "exactly one namespaced product Application",
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
        var productSourcePaths = Directory
            .EnumerateFiles(sourceRoot, "*.*", SearchOption.AllDirectories)
            .Where(path => path.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
            .ToList();
        var productSources = productSourcePaths.Select(File.ReadAllText).ToList();
        var appXaml = ReadAppXaml();
        var persistence = string.Join(
            Environment.NewLine,
            productSourcePaths
                .Where(path => path.Contains(
                    $"{Path.DirectorySeparatorChar}Persistence{Path.DirectorySeparatorChar}",
                    StringComparison.OrdinalIgnoreCase))
                .Select(File.ReadAllText));
        var openRouterClient = File.ReadAllText(Path.Combine(
            sourceRoot,
            "BG3HonorAssistant.Infrastructure",
            "OpenRouter",
            "OpenRouterClient.cs"));
        var credentialStore = File.ReadAllText(Path.Combine(
            sourceRoot,
            "BG3HonorAssistant.Windows",
            "Credentials",
            "CredentialStore.cs"));
        var appProject = File.ReadAllText(Path.Combine(
            sourceRoot,
            "BG3HonorAssistant.App",
            "BG3HonorAssistant.App.csproj"));

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
        Assert.Contains(
            "https://openrouter.ai/api/v1/chat/completions",
            openRouterClient,
            StringComparison.Ordinal);
        Assert.Contains("CredWrite", credentialStore, StringComparison.Ordinal);
        Assert.Contains("CredRead", credentialStore, StringComparison.Ordinal);
        Assert.Contains("CredDelete", credentialStore, StringComparison.Ordinal);
        Assert.DoesNotContain("Environment.", credentialStore, StringComparison.Ordinal);
        Assert.DoesNotContain("File.", credentialStore, StringComparison.Ordinal);
        Assert.DoesNotContain(".env", appProject, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("python", appProject, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("node", appProject, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("ollama", appProject, StringComparison.OrdinalIgnoreCase);

        foreach (var forbiddenApi in new[]
                 {
                     "HttpListener",
                     "TcpListener",
                     "UdpClient",
                     "ReadProcessMemory",
                     "WriteProcessMemory",
                     "CreateRemoteThread",
                     "VirtualAllocEx",
                 })
        {
            Assert.DoesNotContain(
                productSources,
                source => source.Contains(
                    forbiddenApi,
                    StringComparison.OrdinalIgnoreCase));
        }
    }

    [Fact]
    public void LiveCanaryAndPackageGateCannotPersistOrShipExternalSecretsAndRuntimes()
    {
        var canary = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "tests",
            "BG3HonorAssistant.Windows.Tests",
            "Credentials",
            "LiveOpenRouterCanaryTests.cs"));
        var validator = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "package",
            "validate-package-architecture.ps1"));
        var boundaryValidator = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "package",
            "validate-product-boundary.ps1"));
        var settingsXaml = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App",
            "Screens",
            "Settings",
            "SettingsView.xaml"));
        var settingsCode = File.ReadAllText(Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App",
            "Screens",
            "Settings",
            "MainWindow.Settings.cs"));

        Assert.DoesNotContain("OPENROUTER_API_KEY", canary, StringComparison.Ordinal);
        Assert.DoesNotContain("store.Save", canary, StringComparison.Ordinal);
        Assert.DoesNotContain("store.Delete", canary, StringComparison.Ordinal);
        Assert.Contains("store.Read", canary, StringComparison.Ordinal);
        Assert.Contains(
            "CancellationTokenSource(TimeSpan.FromSeconds(30))",
            canary,
            StringComparison.Ordinal);
        Assert.Contains(
            "validate-product-boundary.ps1",
            validator,
            StringComparison.Ordinal);
        Assert.Contains(
            "BG3HonorAssistant.deps.json",
            boundaryValidator,
            StringComparison.Ordinal);
        Assert.Contains(
            "$allowedRootDlls",
            boundaryValidator,
            StringComparison.Ordinal);
        Assert.Contains(
            "Executable content is not allowed under Resources",
            boundaryValidator,
            StringComparison.Ordinal);
        Assert.Contains(
            "Payload is not present in the delivered dependency/resource allowlist",
            boundaryValidator,
            StringComparison.Ordinal);

        Assert.DoesNotContain(
            "google/",
            settingsXaml,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains(
            "OpenRouterModelText.Text = OpenRouterClient.Model",
            settingsCode,
            StringComparison.Ordinal);
    }

    [Fact]
    public void ProductBoundaryRejectsRenamedNativeRuntimeNotInDependencyInventory()
    {
        var temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"BG3HonorAssistant-boundary-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temporaryRoot);
        try
        {
            Directory.CreateDirectory(Path.Combine(temporaryRoot, "Assets"));
            Directory.CreateDirectory(Path.Combine(temporaryRoot, "Resources", "Data"));
            File.WriteAllText(
                Path.Combine(temporaryRoot, "BG3HonorAssistant.deps.json"),
                """
                {
                  "runtimeTarget": {
                    "name": ".NETCoreApp,Version=v10.0/win-arm64"
                  },
                  "targets": {
                    ".NETCoreApp,Version=v10.0/win-arm64": {
                      "BG3HonorAssistant/1.0.0": {
                        "runtime": {
                          "BG3HonorAssistant.dll": {},
                          "BG3HonorAssistant.Core.dll": {},
                          "BG3HonorAssistant.Infrastructure.dll": {},
                          "BG3HonorAssistant.Windows.dll": {}
                        }
                      }
                    }
                  }
                }
                """);
            foreach (var relativePath in new[]
                     {
                         "AppxManifest.xml",
                         "Assets/AppIcon.png",
                         "BG3HonorAssistant.exe",
                         "BG3HonorAssistant.dll",
                         "BG3HonorAssistant.Core.dll",
                         "BG3HonorAssistant.Infrastructure.dll",
                         "BG3HonorAssistant.Windows.dll",
                         "BG3HonorAssistant.runtimeconfig.json",
                         "Resources/Data/guide-bundle.json",
                         "Resources/THIRD_PARTY_NOTICES.md",
                     })
            {
                var path = Path.Combine(
                    temporaryRoot,
                    relativePath.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, "fixture");
            }

            var accepted = RunProductBoundaryValidator(temporaryRoot);
            Assert.Equal(0, accepted.ExitCode);

            Assert.NotNull(Environment.ProcessPath);
            File.Copy(
                Environment.ProcessPath!,
                Path.Combine(temporaryRoot, "pythonw.exe"));

            var rejected = RunProductBoundaryValidator(temporaryRoot);
            Assert.NotEqual(0, rejected.ExitCode);
            Assert.Contains(
                "not present in the delivered dependency/resource allowlist",
                rejected.Output,
                StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(temporaryRoot, recursive: true);
        }
    }

    [Fact]
    public void ProviderCancellationAndCredentialReplacementInvalidatePendingOperations()
    {
        static string Normalize(string path) =>
            File.ReadAllText(path).Replace("\r\n", "\n", StringComparison.Ordinal);

        var appRoot = Path.Combine(
            RepositoryRoot,
            "windows",
            "src",
            "BG3HonorAssistant.App");
        var chat = Normalize(Path.Combine(
            appRoot,
            "Screens",
            "Chat",
            "MainWindow.Chat.cs"));
        var party = Normalize(Path.Combine(
            appRoot,
            "Screens",
            "Party",
            "MainWindow.Party.cs"));
        var settings = Normalize(Path.Combine(
            appRoot,
            "Screens",
            "Settings",
            "MainWindow.Settings.cs"));
        var lifecycle = Normalize(Path.Combine(
            appRoot,
            "Shell",
            "MainWindow.Lifecycle.cs"));

        Assert.Contains(
            "chatOperationVersion++;\n            chatCancellation.Cancel();",
            chat,
            StringComparison.Ordinal);
        Assert.Contains(
            "chatOperationVersion++;\n        chatCancellation?.Cancel();\n        chatLines.Clear();",
            chat,
            StringComparison.Ordinal);
        Assert.Contains(
            "importOperationVersion++;\n            importCancellation.Cancel();",
            party,
            StringComparison.Ordinal);
        Assert.Contains(
            "keyTestOperationVersion++;\n            keyTestCancellation.Cancel();",
            settings,
            StringComparison.Ordinal);
        Assert.Contains(
            "CancelProviderOperations();\n        try\n        {\n            credentialStore.Save(key);",
            settings,
            StringComparison.Ordinal);
        Assert.Contains("CancelProviderOperations();", lifecycle, StringComparison.Ordinal);
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

    private static (int ExitCode, string Output) RunProductBoundaryValidator(
        string payloadRoot)
    {
        var script = Path.Combine(
            RepositoryRoot,
            "windows",
            "package",
            "validate-product-boundary.ps1");
        var start = new System.Diagnostics.ProcessStartInfo("powershell.exe")
        {
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
        };
        foreach (var argument in new[]
                 {
                     "-NoProfile",
                     "-NonInteractive",
                     "-ExecutionPolicy",
                     "Bypass",
                     "-File",
                     script,
                     "-Root",
                     payloadRoot,
                     "-ExpectedArchitecture",
                     "arm64",
                 })
        {
            start.ArgumentList.Add(argument);
        }

        using var process = System.Diagnostics.Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return (process.ExitCode, output + error);
    }
}
