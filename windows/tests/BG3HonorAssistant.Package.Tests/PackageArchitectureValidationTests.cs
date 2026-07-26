using System.Buffers.Binary;
using System.Diagnostics;
using System.Xml.Linq;

namespace BG3HonorAssistant.Package.Tests;

public sealed class PackageArchitectureValidationTests
{
    private const ushort ImageFileMachineI386 = 0x014C;
    private const ushort ImageFileMachineAmd64 = 0x8664;
    private const uint CorIlOnly = 0x00000001;
    private const uint Cor32BitRequired = 0x00000002;
    private const uint CorNativeEntryPoint = 0x00000010;
    private const uint Cor32BitPreferred = 0x00020000;

    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string ValidatorPath = Path.Combine(
        RepositoryRoot,
        "windows",
        "package",
        "validate-package-architecture.ps1");
    private static readonly string ManifestTemplatePath = Path.Combine(
        RepositoryRoot,
        "windows",
        "package",
        "Package.appxmanifest");

    [Fact]
    public async Task NeutralIlIsAcceptedButRealX86ManagedAssemblyIsRejected()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            var neutralPath = typeof(Assert).Assembly.Location;
            File.Copy(
                neutralPath,
                Path.Combine(root, "NeutralManaged.dll"),
                overwrite: true);

            var neutralResult = await RunValidatorAsync(root, "x64");
            Assert.Equal(0, neutralResult.ExitCode);

            var frameworkX86 = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "Microsoft.NET",
                "Framework",
                "v4.0.30319",
                "CustomMarshalers.dll");
            var x86Path = Path.Combine(root, "X86Managed.dll");
            if (File.Exists(frameworkX86))
            {
                File.Copy(frameworkX86, x86Path, overwrite: true);
            }
            else
            {
                File.WriteAllBytes(
                    x86Path,
                    CreateManagedPe(
                        CorIlOnly | Cor32BitRequired,
                        validMetadata: true,
                        hasManagedNativeHeader: false));
            }

            var x86Result = await RunValidatorAsync(root, "x64");
            Assert.NotEqual(0, x86Result.ExitCode);
            Assert.Contains(
                "Cross-architecture PE payload",
                x86Result.CombinedOutput,
                StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task I386ClrBypassesAreRejected()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            var cases = new[]
            {
                new FixtureCase(
                    "32BITREQUIRED",
                    CreateManagedPe(
                        CorIlOnly | Cor32BitRequired,
                        validMetadata: true,
                        hasManagedNativeHeader: false),
                    "Cross-architecture PE payload"),
                new FixtureCase(
                    "32BITPREFERRED",
                    CreateManagedPe(
                        CorIlOnly | Cor32BitPreferred,
                        validMetadata: true,
                        hasManagedNativeHeader: false),
                    "Cross-architecture PE payload"),
                new FixtureCase(
                    "mixed-mode",
                    CreateManagedPe(
                        corFlags: 0,
                        validMetadata: true,
                        hasManagedNativeHeader: false),
                    "Cross-architecture PE payload"),
                new FixtureCase(
                    "native-entry-point",
                    CreateManagedPe(
                        CorIlOnly | CorNativeEntryPoint,
                        validMetadata: true,
                        hasManagedNativeHeader: false),
                    "Cross-architecture PE payload"),
                new FixtureCase(
                    "ready-to-run",
                    CreateManagedPe(
                        CorIlOnly,
                        validMetadata: true,
                        hasManagedNativeHeader: true),
                    "Cross-architecture PE payload"),
                new FixtureCase(
                    "forged-metadata",
                    CreateManagedPe(
                        CorIlOnly,
                        validMetadata: false,
                        hasManagedNativeHeader: false),
                    "CLR metadata signature or size is invalid"),
                new FixtureCase(
                    "malformed-cli-directory",
                    CreateManagedPe(
                        CorIlOnly,
                        validMetadata: true,
                        hasManagedNativeHeader: false,
                        cliRva: 1,
                        cliSize: 0),
                    "CLI data directory has an inconsistent RVA/size"),
            };

            var fixturePath = Path.Combine(root, "Contaminant.dll");
            foreach (var fixture in cases)
            {
                File.WriteAllBytes(fixturePath, fixture.Payload);
                var result = await RunValidatorAsync(root, "x64");
                Assert.True(
                    result.ExitCode != 0,
                    $"{fixture.Name} unexpectedly passed.{Environment.NewLine}" +
                    result.CombinedOutput);
                Assert.Contains(
                    fixture.ExpectedError,
                    result.CombinedOutput,
                    StringComparison.Ordinal);
            }
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task ValidNativePeWithShortDataDirectoryTableIsAccepted()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            File.WriteAllBytes(
                Path.Combine(root, "NativeWithoutCliDirectory.dll"),
                CreateNativePe(
                    ImageFileMachineAmd64,
                    numberOfDataDirectories: 0,
                    compactOptionalHeader: true));

            var result = await RunValidatorAsync(root, "x64");
            Assert.Equal(0, result.ExitCode);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task MainExecutableRequiresLaunchableNativeHostStructure()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            var pe32Header = CreateNativePe(ImageFileMachineAmd64);
            WriteUInt16(pe32Header, 0x80 + 24, 0x010B);
            var cases = new[]
            {
                new FixtureCase(
                    "PE32-optional-header",
                    pe32Header,
                    "must use a PE32+ optional header"),
                new FixtureCase(
                    "missing-entry-point",
                    CreateNativePe(
                        ImageFileMachineAmd64,
                        addressOfEntryPoint: 0),
                    "has no native entry point"),
                new FixtureCase(
                    "unmapped-entry-point",
                    CreateNativePe(
                        ImageFileMachineAmd64,
                        addressOfEntryPoint: 0x5000),
                    "Application entry point"),
                new FixtureCase(
                    "non-executable-entry-section",
                    CreateNativePe(
                        ImageFileMachineAmd64,
                        sectionCharacteristics: 0x40000040),
                    "entry point must map to exactly one executable"),
                new FixtureCase(
                    "dll-image",
                    CreateNativePe(
                        ImageFileMachineAmd64,
                        coffCharacteristics: 0x2002),
                    "must be an executable image"),
            };

            var executablePath = Path.Combine(root, "BG3HonorAssistant.exe");
            foreach (var fixture in cases)
            {
                File.WriteAllBytes(executablePath, fixture.Payload);
                var result = await RunValidatorAsync(root, "x64");
                Assert.True(
                    result.ExitCode != 0,
                    $"{fixture.Name} unexpectedly passed.{Environment.NewLine}" +
                    result.CombinedOutput);
                Assert.Contains(
                    fixture.ExpectedError,
                    result.CombinedOutput,
                    StringComparison.Ordinal);
            }
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestRejectsAdditionalOrForeignApplicationAndExecutableReferences()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            var manifestPath = Path.Combine(root, "AppxManifest.xml");
            var manifest = XDocument.Load(manifestPath);
            XNamespace foundation =
                "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
            var applications = Assert.Single(
                manifest.Descendants(foundation + "Applications"));
            var application = Assert.Single(
                manifest.Descendants(foundation + "Application"));
            applications.Add(new XElement(application));
            manifest.Save(manifestPath);

            var extraApplication = await RunValidatorAsync(root, "x64");
            Assert.NotEqual(0, extraApplication.ExitCode);
            Assert.Contains(
                "exactly one namespaced product Application",
                extraApplication.CombinedOutput,
                StringComparison.Ordinal);

            WriteManifest(root, "x64");
            manifest = XDocument.Load(manifestPath);
            applications = Assert.Single(
                manifest.Descendants(foundation + "Applications"));
            applications.Add(
                new XElement(
                    XName.Get("Application", "urn:bg3-test-foreign"),
                    new XAttribute("Executable", "BG3HonorAssistant.exe")));
            manifest.Save(manifestPath);

            var foreignApplication = await RunValidatorAsync(root, "x64");
            Assert.NotEqual(0, foreignApplication.ExitCode);
            Assert.Contains(
                "deceptive foreign-namespace Application",
                foreignApplication.CombinedOutput,
                StringComparison.Ordinal);

            WriteManifest(root, "x64");
            manifest = XDocument.Load(manifestPath);
            var executableNode = Assert.Single(
                manifest.Descendants(),
                element =>
                    element.Name.LocalName == "Extension" &&
                    element.Attribute("Executable") is not null);
            executableNode.SetAttributeValue("Executable", "UnexpectedHelper.exe");
            manifest.Save(manifestPath);

            var extraExecutable = await RunValidatorAsync(root, "x64");
            Assert.NotEqual(0, extraExecutable.ExitCode);
            Assert.Contains(
                "Every manifest executable reference must be exactly",
                extraExecutable.CombinedOutput,
                StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestRejectsMismatchedApplicationExecutable()
    {
        var root = CreateLayout("x64", ImageFileMachineAmd64);
        try
        {
            var manifestPath = Path.Combine(root, "AppxManifest.xml");
            var manifest = XDocument.Load(manifestPath);
            XNamespace foundation =
                "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
            var application = Assert.Single(
                manifest.Descendants(foundation + "Application"));
            application.SetAttributeValue("Executable", "Other.exe");
            manifest.Save(manifestPath);

            var result = await RunValidatorAsync(root, "x64");
            Assert.NotEqual(0, result.ExitCode);
            Assert.Contains(
                "Application executable must be exactly",
                result.CombinedOutput,
                StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string CreateLayout(string architecture, ushort mainMachine)
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"BG3HonorAssistant-package-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        WriteManifest(root, architecture);
        File.WriteAllBytes(
            Path.Combine(root, "BG3HonorAssistant.exe"),
            CreateNativePe(mainMachine));
        return root;
    }

    private static void WriteManifest(string root, string architecture)
    {
        var manifest = XDocument.Load(ManifestTemplatePath);
        XNamespace foundation =
            "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
        var identity = Assert.Single(manifest.Descendants(foundation + "Identity"));
        identity.SetAttributeValue("ProcessorArchitecture", architecture);
        manifest.Save(Path.Combine(root, "AppxManifest.xml"));
    }

    private static byte[] CreateNativePe(
        ushort machine,
        uint addressOfEntryPoint = 0x2000,
        ushort coffCharacteristics = 0x0002,
        uint sectionCharacteristics = 0x60000020,
        uint numberOfDataDirectories = 16,
        bool compactOptionalHeader = false)
    {
        return CreatePe(
            machine,
            cliRva: 0,
            cliSize: 0,
            corFlags: 0,
            validMetadata: false,
            hasManagedNativeHeader: false,
            addressOfEntryPoint: addressOfEntryPoint,
            coffCharacteristics: coffCharacteristics,
            sectionCharacteristics: sectionCharacteristics,
            numberOfDataDirectories: numberOfDataDirectories,
            compactOptionalHeader: compactOptionalHeader);
    }

    private static byte[] CreateManagedPe(
        uint corFlags,
        bool validMetadata,
        bool hasManagedNativeHeader,
        uint cliRva = 0x2000,
        uint cliSize = 72)
    {
        return CreatePe(
            ImageFileMachineI386,
            cliRva,
            cliSize,
            corFlags,
            validMetadata,
            hasManagedNativeHeader);
    }

    private static byte[] CreatePe(
        ushort machine,
        uint cliRva,
        uint cliSize,
        uint corFlags,
        bool validMetadata,
        bool hasManagedNativeHeader,
        uint addressOfEntryPoint = 0x2000,
        ushort coffCharacteristics = 0x0002,
        uint sectionCharacteristics = 0x60000020,
        uint numberOfDataDirectories = 16,
        bool compactOptionalHeader = false)
    {
        const int peOffset = 0x80;
        var pe32Plus = machine != ImageFileMachineI386;
        var dataDirectoryOffset = pe32Plus ? 112 : 96;
        var optionalHeaderSize = compactOptionalHeader
            ? dataDirectoryOffset
            : pe32Plus ? 240 : 224;
        var optionalHeaderOffset = peOffset + 24;
        var sectionHeaderOffset = optionalHeaderOffset + optionalHeaderSize;
        var bytes = new byte[0x600];

        WriteUInt16(bytes, 0, 0x5A4D);
        WriteUInt32(bytes, 0x3C, peOffset);
        WriteUInt32(bytes, peOffset, 0x00004550);
        WriteUInt16(bytes, peOffset + 4, machine);
        WriteUInt16(bytes, peOffset + 6, 1);
        WriteUInt16(bytes, peOffset + 20, (ushort)optionalHeaderSize);
        WriteUInt16(bytes, peOffset + 22, coffCharacteristics);
        WriteUInt16(
            bytes,
            optionalHeaderOffset,
            pe32Plus ? (ushort)0x020B : (ushort)0x010B);
        WriteUInt32(bytes, optionalHeaderOffset + 16, addressOfEntryPoint);
        WriteUInt16(
            bytes,
            optionalHeaderOffset + 68,
            2);
        WriteUInt32(
            bytes,
            optionalHeaderOffset + (pe32Plus ? 108 : 92),
            numberOfDataDirectories);
        if (numberOfDataDirectories >= 15 && !compactOptionalHeader)
        {
            WriteUInt32(
                bytes,
                optionalHeaderOffset + dataDirectoryOffset + (14 * 8),
                cliRva);
            WriteUInt32(
                bytes,
                optionalHeaderOffset + dataDirectoryOffset + (14 * 8) + 4,
                cliSize);
        }

        bytes[sectionHeaderOffset] = (byte)'.';
        bytes[sectionHeaderOffset + 1] = (byte)'t';
        bytes[sectionHeaderOffset + 2] = (byte)'e';
        bytes[sectionHeaderOffset + 3] = (byte)'x';
        bytes[sectionHeaderOffset + 4] = (byte)'t';
        WriteUInt32(bytes, sectionHeaderOffset + 8, 0x400);
        WriteUInt32(bytes, sectionHeaderOffset + 12, 0x2000);
        WriteUInt32(bytes, sectionHeaderOffset + 16, 0x400);
        WriteUInt32(bytes, sectionHeaderOffset + 20, 0x200);
        WriteUInt32(bytes, sectionHeaderOffset + 36, sectionCharacteristics);

        if (cliRva == 0x2000 && cliSize >= 72)
        {
            const int cliOffset = 0x200;
            WriteUInt32(bytes, cliOffset, 72);
            WriteUInt16(bytes, cliOffset + 4, 2);
            WriteUInt16(bytes, cliOffset + 6, 5);
            WriteUInt32(bytes, cliOffset + 8, 0x2080);
            WriteUInt32(bytes, cliOffset + 12, 0x40);
            WriteUInt32(bytes, cliOffset + 16, corFlags);
            if (hasManagedNativeHeader)
            {
                WriteUInt32(bytes, cliOffset + 64, 0x20C0);
                WriteUInt32(bytes, cliOffset + 68, 4);
            }
            WriteUInt32(
                bytes,
                0x280,
                validMetadata ? 0x424A5342u : 0xDEADBEEFu);
        }

        return bytes;
    }

    private static void WriteUInt16(byte[] bytes, int offset, ushort value)
    {
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(offset), value);
    }

    private static void WriteUInt32(byte[] bytes, int offset, uint value)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset), value);
    }

    private static async Task<ValidatorResult> RunValidatorAsync(
        string root,
        string architecture)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = GetNativePowerShellPath(),
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(ValidatorPath);
        startInfo.ArgumentList.Add("-Root");
        startInfo.ArgumentList.Add(root);
        startInfo.ArgumentList.Add("-ExpectedArchitecture");
        startInfo.ArgumentList.Add(architecture);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Could not start PowerShell.");
        var standardOutput = process.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return new ValidatorResult(
            process.ExitCode,
            (await standardOutput) + Environment.NewLine + (await standardError));
    }

    private static string GetNativePowerShellPath()
    {
        var windowsRoot =
            Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var sysnative = Path.Combine(
            windowsRoot,
            "Sysnative",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        if (File.Exists(sysnative))
        {
            return sysnative;
        }
        return Path.Combine(
            windowsRoot,
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
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

    private sealed record FixtureCase(
        string Name,
        byte[] Payload,
        string ExpectedError);

    private sealed record ValidatorResult(int ExitCode, string CombinedOutput);
}
