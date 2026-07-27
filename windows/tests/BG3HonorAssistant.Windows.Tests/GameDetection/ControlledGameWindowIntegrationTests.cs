using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Overlay;
using Xunit.Abstractions;

namespace BG3HonorAssistant.Windows.Tests.GameDetection;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ControlledGameWindowCollection
{
    public const string Name = "Controlled game window";
}

[Collection(ControlledGameWindowCollection.Name)]
public sealed class ControlledGameWindowIntegrationTests
{
    private static readonly TimeSpan OperationTimeout = TimeSpan.FromSeconds(30);
    private readonly ITestOutputHelper output;

    public ControlledGameWindowIntegrationTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Theory]
    [InlineData("bg3", true)]
    [InlineData("bg3_dx11", false)]
    public void ExactNameHostExercisesDetectionFollowingAndLifecycle(
        string processName,
        bool borderless)
    {
        var architecture = ControlledHostArchitecture.FromEnvironmentOrProcess();
        using var host = ControlledGameHost.Start(
            processName,
            borderless,
            architecture);
        Assert.Equal(
            architecture.PortableExecutableMachine,
            host.PortableExecutableMachine);
        Assert.True(
            host.ProcessArchitecture.IsExpectedFor(architecture),
            $"Expected {architecture.RuntimeIdentifier}; observed " +
            $"{host.ProcessArchitecture.DescribeFor(architecture)}.");
        var locator = new Bg3WindowLocator();
        var initial = WaitForWindow(
            locator,
            candidate => candidate.ProcessId == host.Process.Id);

        Assert.Equal(processName, initial.ProcessName, ignoreCase: true);
        Assert.Equal(host.WindowHandle, initial.WindowHandle);
        Assert.Equal(checked((uint)ControlledNativeMethods.GetDpiForWindow(host.WindowHandle)), initial.Dpi);
        Assert.True(initial.Bounds.IsUsable);

        var observed = new List<Bg3WindowInfo?>();
        using var monitor = new Bg3WindowMonitor(locator);
        monitor.WindowChanged += (_, eventArgs) => observed.Add(eventArgs.Window);
        monitor.Refresh();
        Assert.Equal(host.Process.Id, monitor.Current?.ProcessId);

        using var overlay = TestOverlayWindow.Create();
        var overlayService = new OverlayWindowService();
        overlayService.Configure(overlay.Handle, passive: true);
        _ = ControlledNativeMethods.SetForegroundWindow(host.WindowHandle);
        WaitFor(
            () => ControlledNativeMethods.GetForegroundWindow() == host.WindowHandle ||
                  ControlledNativeMethods.GetForegroundWindow() != nint.Zero);
        var foregroundBefore = ControlledNativeMethods.GetForegroundWindow();

        overlayService.PositionRelativeTo(
            overlay.Handle,
            initial,
            widthInDeviceIndependentPixels: 380,
            heightInDeviceIndependentPixels: 250);

        Assert.Equal(foregroundBefore, ControlledNativeMethods.GetForegroundWindow());
        Assert.True(ControlledNativeMethods.GetWindowRect(overlay.Handle, out var overlayBounds));
        Assert.InRange(overlayBounds.Left, initial.Bounds.Left, initial.Bounds.Right - 1);
        Assert.InRange(overlayBounds.Top, initial.Bounds.Top, initial.Bounds.Bottom - 1);

        overlayService.SetPassive(overlay.Handle, passive: false);
        var interactiveStyles = ControlledNativeMethods
            .GetWindowLongPtr(overlay.Handle, ControlledNativeMethods.GwlExStyle)
            .ToInt64();
        Assert.Equal(0, interactiveStyles & ControlledNativeMethods.WsExNoActivate);

        overlayService.SetPassive(overlay.Handle, passive: true);
        var passiveStyles = ControlledNativeMethods
            .GetWindowLongPtr(overlay.Handle, ControlledNativeMethods.GwlExStyle)
            .ToInt64();
        Assert.NotEqual(0, passiveStyles & ControlledNativeMethods.WsExNoActivate);
        var headlessCi = string.Equals(
            Environment.GetEnvironmentVariable("BG3_HEADLESS_CI"),
            "1",
            StringComparison.Ordinal);
        if (!headlessCi)
        {
            _ = ControlledNativeMethods.SetForegroundWindow(host.WindowHandle);
            WaitFor(() => ControlledNativeMethods.GetForegroundWindow() == host.WindowHandle);
        }

        foregroundBefore = ControlledNativeMethods.GetForegroundWindow();
        Assert.True(
            foregroundBefore != nint.Zero,
            "The controlled-window test requires a live desktop foreground window.");

        Assert.True(
            ControlledNativeMethods.SetWindowPos(
                host.WindowHandle,
                nint.Zero,
                -900,
                64,
                960,
                540,
                ControlledNativeMethods.SwpNoZOrder |
                ControlledNativeMethods.SwpNoActivate |
                ControlledNativeMethods.SwpShowWindow),
            new Win32Exception(Marshal.GetLastPInvokeError()).Message);

        var moved = WaitForWindow(
            locator,
            candidate =>
                candidate.ProcessId == host.Process.Id &&
                candidate.Bounds.Left < 0 &&
                candidate.Bounds != initial.Bounds);
        Assert.True(moved.Bounds.IsUsable);
        Assert.Equal(
            checked((uint)ControlledNativeMethods.GetDpiForWindow(host.WindowHandle)),
            moved.Dpi);

        monitor.Refresh();
        Assert.Equal(moved, monitor.Current);
        overlayService.PositionRelativeTo(overlay.Handle, moved, 380, 250);
        Assert.Equal(foregroundBefore, ControlledNativeMethods.GetForegroundWindow());
        Assert.True(ControlledNativeMethods.GetWindowRect(overlay.Handle, out overlayBounds));
        Assert.InRange(overlayBounds.Left, moved.Bounds.Left, moved.Bounds.Right - 1);
        Assert.InRange(overlayBounds.Top, moved.Bounds.Top, moved.Bounds.Bottom - 1);

        Assert.True(ControlledNativeMethods.ShowWindow(host.WindowHandle, ControlledNativeMethods.SwMinimize));
        WaitFor(() => ControlledNativeMethods.IsIconic(host.WindowHandle));
        WaitFor(() => locator.FindBestWindow() is null);
        monitor.Refresh();
        Assert.Null(monitor.Current);

        _ = ControlledNativeMethods.ShowWindow(host.WindowHandle, ControlledNativeMethods.SwRestore);
        var restored = WaitForWindow(
            locator,
            candidate => candidate.ProcessId == host.Process.Id);
        monitor.Refresh();
        Assert.Equal(restored, monitor.Current);

        Assert.True(
            ControlledNativeMethods.PostMessage(
                host.WindowHandle,
                ControlledNativeMethods.WmClose,
                nint.Zero,
                nint.Zero));
        Assert.True(host.Process.WaitForExit(checked((int)OperationTimeout.TotalMilliseconds)));
        WaitFor(() => locator.FindBestWindow() is null);
        monitor.Refresh();
        Assert.Null(monitor.Current);

        using var relaunched = ControlledGameHost.Start(
            processName,
            borderless,
            architecture);
        Assert.True(
            relaunched.ProcessArchitecture.IsExpectedFor(architecture),
            $"Expected relaunched {architecture.RuntimeIdentifier}; observed " +
            $"{relaunched.ProcessArchitecture.DescribeFor(architecture)}.");
        var relaunchedWindow = WaitForWindow(
            locator,
            candidate => candidate.ProcessId == relaunched.Process.Id);
        Assert.NotEqual(host.Process.Id, relaunchedWindow.ProcessId);
        monitor.Refresh();
        Assert.Equal(relaunchedWindow, monitor.Current);

        Assert.True(
            ControlledNativeMethods.PostMessage(
                relaunched.WindowHandle,
                ControlledNativeMethods.WmClose,
                nint.Zero,
                nint.Zero));
        Assert.True(
            relaunched.Process.WaitForExit(
                checked((int)OperationTimeout.TotalMilliseconds)));
        WaitFor(() => locator.FindBestWindow() is null);
        monitor.Refresh();
        Assert.Null(monitor.Current);

        Assert.Contains(observed, candidate => candidate?.Bounds == moved.Bounds);
        Assert.Contains(observed, candidate => candidate is null);
        Assert.Contains(observed, candidate => candidate?.Bounds == restored.Bounds);
        Assert.Contains(
            observed,
            candidate => candidate?.ProcessId == relaunched.Process.Id);

        output.WriteLine(
            "host={0}.exe; mode={1}; rid={2}; pe=0x{3:X4}; host-process={4}; pid={5}; relaunch-pid={6}; initial={7}; moved={8}; restored={9}; dpi={10}; monitors={11}; os={12}; os-architecture={13}; test-process={14}; pointer-size={15}",
            processName,
            borderless ? "borderless-style" : "windowed-style",
            architecture.RuntimeIdentifier,
            host.PortableExecutableMachine,
            host.ProcessArchitecture.DescribeFor(architecture),
            host.Process.Id,
            relaunched.Process.Id,
            initial.Bounds,
            moved.Bounds,
            restored.Bounds,
            restored.Dpi,
            ControlledNativeMethods.GetSystemMetrics(ControlledNativeMethods.SmCmonitors),
            Environment.OSVersion.VersionString,
            RuntimeInformation.OSArchitecture,
            RuntimeInformation.ProcessArchitecture,
            nint.Size);
    }

    [Theory]
    [InlineData("bg3.exe.exe")]
    [InlineData("bg3.scr")]
    [InlineData("bg3_dx11.com")]
    public void LookalikeImageNamesAreRejectedEndToEnd(string executableFileName)
    {
        var architecture = ControlledHostArchitecture.FromEnvironmentOrProcess();
        using var host = ControlledGameHost.StartExecutable(
            executableFileName,
            borderless: false,
            architecture);

        var located = new Bg3WindowLocator().FindBestWindow();

        Assert.NotEqual(host.Process.Id, located?.ProcessId);
    }

    [Fact]
    public void HostLookupUsesIntegratedArchitectureDirectory()
    {
        var architecture = new ControlledHostArchitecture(
            "win-arm64",
            ControlledHostArchitecture.Arm64Machine);
        var windowsRoot = CreateHostLayoutRoot();
        try
        {
            var integratedOutput = Path.Combine(
                windowsRoot,
                "spikes",
                "GameWindowHost",
                "bin",
                "arm64",
                "Debug",
                "net10.0-windows10.0.26100.0",
                architecture.RuntimeIdentifier);
            WritePortableExecutable(
                integratedOutput,
                architecture.PortableExecutableMachine);

            Assert.Equal(
                integratedOutput,
                ControlledGameHost.FindHostOutput(
                    windowsRoot,
                    architecture,
                    "Debug"));
        }
        finally
        {
            Assert.True(ControlledGameHost.TryDeleteDirectory(windowsRoot));
        }
    }

    [Fact]
    public void HostLookupRejectsConflictingArchitectureOutputs()
    {
        var architecture = new ControlledHostArchitecture(
            "win-arm64",
            ControlledHostArchitecture.Arm64Machine);
        var windowsRoot = CreateHostLayoutRoot();
        try
        {
            WritePortableExecutable(
                Path.Combine(
                    windowsRoot,
                    "spikes",
                    "GameWindowHost",
                    "bin",
                    "arm64",
                    "Debug",
                    "net10.0-windows10.0.26100.0",
                    architecture.RuntimeIdentifier),
                architecture.PortableExecutableMachine);
            WritePortableExecutable(
                Path.Combine(
                    windowsRoot,
                    "spikes",
                    "GameWindowHost",
                    "bin",
                    "Debug",
                    "net10.0-windows10.0.26100.0",
                    architecture.RuntimeIdentifier),
                ControlledHostArchitecture.Amd64Machine);

            var exception = Assert.Throws<InvalidDataException>(
                () => ControlledGameHost.FindHostOutput(
                    windowsRoot,
                    architecture,
                    "Debug"));
            Assert.Contains("conflicting PE machine", exception.Message);
        }
        finally
        {
            Assert.True(ControlledGameHost.TryDeleteDirectory(windowsRoot));
        }
    }

    private static string CreateHostLayoutRoot()
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            "BG3HonorAssistant",
            "host-layout",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static void WritePortableExecutable(
        string outputDirectory,
        ushort machine)
    {
        Directory.CreateDirectory(outputDirectory);
        var bytes = new byte[256];
        BitConverter.GetBytes(128).CopyTo(bytes, 0x3C);
        bytes[128] = (byte)'P';
        bytes[129] = (byte)'E';
        BitConverter.GetBytes(machine).CopyTo(bytes, 132);
        File.WriteAllBytes(
            Path.Combine(outputDirectory, "GameWindowHost.exe"),
            bytes);
    }

    private readonly record struct ControlledHostArchitecture(
        string RuntimeIdentifier,
        ushort PortableExecutableMachine)
    {
        internal const string EnvironmentVariable = "BG3_CONTROLLED_HOST_RID";
        internal const ushort Amd64Machine = 0x8664;
        internal const ushort Arm64Machine = 0xAA64;

        internal string ArchitectureDirectory => RuntimeIdentifier switch
        {
            "win-arm64" => "arm64",
            "win-x64" => "x64",
            _ => throw new InvalidOperationException(
                $"Unsupported controlled-host RID '{RuntimeIdentifier}'."),
        };

        internal static ControlledHostArchitecture FromEnvironmentOrProcess()
        {
            var runtimeIdentifier = Environment.GetEnvironmentVariable(
                EnvironmentVariable);
            return runtimeIdentifier switch
            {
                "win-arm64" => new(runtimeIdentifier, Arm64Machine),
                "win-x64" => new(runtimeIdentifier, Amd64Machine),
                null or "" => RuntimeInformation.ProcessArchitecture switch
                {
                    Architecture.Arm64 => new("win-arm64", Arm64Machine),
                    Architecture.X64 => new("win-x64", Amd64Machine),
                    _ => throw new PlatformNotSupportedException(
                        "Controlled BG3 hosts support exactly ARM64 and x64 test processes."),
                },
                _ => throw new InvalidOperationException(
                    $"{EnvironmentVariable} supports exactly win-arm64 and win-x64; " +
                    $"received '{runtimeIdentifier}'."),
            };
        }
    }

    private readonly record struct ProcessArchitectureObservation(
        ushort ProcessMachine,
        ushort NativeMachine)
    {
        internal bool IsExpectedFor(ControlledHostArchitecture expected)
        {
            return expected.RuntimeIdentifier switch
            {
                "win-arm64" =>
                    ProcessMachine == ControlledNativeMethods.ImageFileMachineUnknown &&
                    NativeMachine == ControlledHostArchitecture.Arm64Machine,
                "win-x64" =>
                    (ProcessMachine == ControlledNativeMethods.ImageFileMachineUnknown &&
                     NativeMachine == ControlledHostArchitecture.Amd64Machine) ||
                    ((ProcessMachine == ControlledNativeMethods.ImageFileMachineUnknown ||
                      ProcessMachine == ControlledHostArchitecture.Amd64Machine) &&
                     NativeMachine == ControlledHostArchitecture.Arm64Machine),
                _ => false,
            };
        }

        internal string DescribeFor(ControlledHostArchitecture image)
        {
            return (image.RuntimeIdentifier, NativeMachine) switch
            {
                ("win-arm64", ControlledHostArchitecture.Arm64Machine) =>
                    "native-isa-arm64",
                ("win-x64", ControlledHostArchitecture.Amd64Machine) =>
                    "native-isa-x64",
                ("win-x64", ControlledHostArchitecture.Arm64Machine) =>
                    "emulated-x64-on-arm64",
                _ =>
                    $"{MachineName(image.PortableExecutableMachine)}-image-on-" +
                    $"{MachineName(NativeMachine)}",
            };
        }

        private static string MachineName(ushort machine)
        {
            return machine switch
            {
                ControlledHostArchitecture.Arm64Machine => "arm64",
                ControlledHostArchitecture.Amd64Machine => "x64",
                _ => $"machine-0x{machine:X4}",
            };
        }
    }

    private static Bg3WindowInfo WaitForWindow(
        IBg3WindowLocator locator,
        Func<Bg3WindowInfo, bool> predicate)
    {
        Bg3WindowInfo? result = null;
        WaitFor(
            () =>
            {
                result = locator.FindBestWindow();
                return result is not null && predicate(result);
            });
        return result!;
    }

    private static void WaitFor(Func<bool> condition)
    {
        var stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < OperationTimeout)
        {
            if (condition())
            {
                return;
            }

            Thread.Sleep(50);
        }

        throw new TimeoutException(
            $"The controlled-window condition did not complete within {OperationTimeout}.");
    }

    private sealed class TestOverlayWindow : IDisposable
    {
        private TestOverlayWindow(nint handle)
        {
            Handle = handle;
        }

        internal nint Handle { get; }

        internal static TestOverlayWindow Create()
        {
            var handle = ControlledNativeMethods.CreateWindowEx(
                0,
                "STATIC",
                "BG3 Honor Assistant controlled overlay",
                ControlledNativeMethods.WsPopup,
                0,
                0,
                100,
                100,
                nint.Zero,
                nint.Zero,
                nint.Zero,
                nint.Zero);
            if (handle == nint.Zero)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }

            return new TestOverlayWindow(handle);
        }

        public void Dispose()
        {
            if (!ControlledNativeMethods.DestroyWindow(Handle))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }
        }
    }

    private sealed class ControlledGameHost : IDisposable
    {
        private ControlledGameHost(
            string stagingDirectory,
            Process process,
            nint windowHandle,
            ushort portableExecutableMachine,
            ProcessArchitectureObservation processArchitecture)
        {
            StagingDirectory = stagingDirectory;
            Process = process;
            WindowHandle = windowHandle;
            PortableExecutableMachine = portableExecutableMachine;
            ProcessArchitecture = processArchitecture;
        }

        private string StagingDirectory { get; }

        internal Process Process { get; }

        internal nint WindowHandle { get; }

        internal ushort PortableExecutableMachine { get; }

        internal ProcessArchitectureObservation ProcessArchitecture { get; }

        internal static ControlledGameHost Start(
            string processName,
            bool borderless,
            ControlledHostArchitecture architecture)
        {
            return StartExecutable(
                $"{processName}.exe",
                borderless,
                architecture);
        }

        internal static ControlledGameHost StartExecutable(
            string executableFileName,
            bool borderless,
            ControlledHostArchitecture architecture)
        {
            if (!string.Equals(
                    Path.GetFileName(executableFileName),
                    executableFileName,
                    StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "The controlled executable must be a file name, not a path.",
                    nameof(executableFileName));
            }

            var sourceDirectory = FindHostOutput(architecture);
            var portableExecutableMachine = ReadPortableExecutableMachine(
                Path.Combine(sourceDirectory, "GameWindowHost.exe"));
            if (portableExecutableMachine != architecture.PortableExecutableMachine)
            {
                throw new InvalidDataException(
                    $"GameWindowHost PE machine 0x{portableExecutableMachine:X4} does not " +
                    $"match {architecture.RuntimeIdentifier} " +
                    $"(0x{architecture.PortableExecutableMachine:X4}).");
            }
            var stagingRoot = Path.Combine(
                Path.GetTempPath(),
                "BG3HonorAssistant",
                "controlled-game-window");
            Directory.CreateDirectory(stagingRoot);
            foreach (var staleDirectory in Directory.EnumerateDirectories(stagingRoot))
            {
                _ = TryDeleteDirectory(staleDirectory);
            }

            var stagingDirectory = Path.Combine(
                stagingRoot,
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stagingDirectory);

            foreach (var sourcePath in Directory.EnumerateFiles(sourceDirectory))
            {
                File.Copy(
                    sourcePath,
                    Path.Combine(stagingDirectory, Path.GetFileName(sourcePath)));
            }

            var executablePath = Path.Combine(
                stagingDirectory,
                executableFileName);
            File.Copy(
                Path.Combine(stagingDirectory, "GameWindowHost.exe"),
                executablePath);

            var arguments = borderless
                ? "--borderless --title \"BG3 controlled borderless host\""
                : "--title \"BG3 controlled windowed host\"";
            var process = Process.Start(
                new ProcessStartInfo
                {
                    FileName = executablePath,
                    Arguments = arguments,
                    UseShellExecute = false,
                    WorkingDirectory = stagingDirectory,
                }) ?? throw new InvalidOperationException("The controlled game host did not start.");

            nint handle = nint.Zero;
            try
            {
                WaitFor(
                    () =>
                    {
                        process.Refresh();
                        handle = process.MainWindowHandle;
                        return handle != nint.Zero &&
                               ControlledNativeMethods.IsWindowVisible(handle);
                    });
                return new ControlledGameHost(
                    stagingDirectory,
                    process,
                    handle,
                    portableExecutableMachine,
                    ReadProcessArchitecture(process));
            }
            catch
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    _ = process.WaitForExit(5000);
                }

                process.Dispose();
                _ = TryDeleteDirectory(stagingDirectory);
                throw;
            }
        }

        public void Dispose()
        {
            if (!Process.HasExited)
            {
                _ = ControlledNativeMethods.PostMessage(
                    WindowHandle,
                    ControlledNativeMethods.WmClose,
                    nint.Zero,
                    nint.Zero);
                if (!Process.WaitForExit(3000))
                {
                    Process.Kill(entireProcessTree: true);
                    _ = Process.WaitForExit(5000);
                }
            }

            Process.Dispose();
            _ = TryDeleteDirectory(StagingDirectory);
        }

        private static string FindHostOutput(
            ControlledHostArchitecture architecture)
        {
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while (directory is not null)
            {
                if (File.Exists(Path.Combine(directory.FullName, "BG3HonorAssistant.slnx")))
                {
#if DEBUG
                    const string configuration = "Debug";
#else
                    const string configuration = "Release";
#endif
                    return FindHostOutput(
                        directory.FullName,
                        architecture,
                        configuration);
                }

                directory = directory.Parent;
            }

            throw new DirectoryNotFoundException(
                "Could not locate the Windows solution root for GameWindowHost.");
        }

        internal static string FindHostOutput(
            string windowsRoot,
            ControlledHostArchitecture architecture,
            string configuration)
        {
            var hostRoot = Path.Combine(
                windowsRoot,
                "spikes",
                "GameWindowHost",
                "bin");
            var integratedOutput = Path.Combine(
                hostRoot,
                architecture.ArchitectureDirectory,
                configuration,
                "net10.0-windows10.0.26100.0",
                architecture.RuntimeIdentifier);
            var legacyOutput = Path.Combine(
                hostRoot,
                configuration,
                "net10.0-windows10.0.26100.0",
                architecture.RuntimeIdentifier);
            var candidates = new[]
            {
                Path.Combine(integratedOutput, "publish"),
                integratedOutput,
                Path.Combine(legacyOutput, "publish"),
                legacyOutput,
            };
            var existing = candidates
                .Where(candidate =>
                    File.Exists(Path.Combine(candidate, "GameWindowHost.exe")))
                .ToList();
            foreach (var candidate in existing)
            {
                var executablePath = Path.Combine(
                    candidate,
                    "GameWindowHost.exe");
                var machine = ReadPortableExecutableMachine(executablePath);
                if (machine != architecture.PortableExecutableMachine)
                {
                    throw new InvalidDataException(
                        $"Controlled-host output '{executablePath}' has conflicting PE " +
                        $"machine 0x{machine:X4}; expected " +
                        $"0x{architecture.PortableExecutableMachine:X4} for " +
                        $"{architecture.RuntimeIdentifier}.");
                }
            }

            return existing.FirstOrDefault() ??
                   throw new FileNotFoundException(
                       $"Build GameWindowHost with the explicit RID " +
                       $"{architecture.RuntimeIdentifier} before running the " +
                       "controlled-window tests.",
                       Path.Combine(integratedOutput, "GameWindowHost.exe"));
        }

        private static ProcessArchitectureObservation ReadProcessArchitecture(
            Process process)
        {
            if (!ControlledNativeMethods.IsWow64Process2(
                    process.Handle,
                    out var processMachine,
                    out var nativeMachine))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }

            return new ProcessArchitectureObservation(
                processMachine,
                nativeMachine);
        }

        private static ushort ReadPortableExecutableMachine(string executablePath)
        {
            using var stream = File.OpenRead(executablePath);
            using var reader = new BinaryReader(stream);
            stream.Position = 0x3C;
            var portableExecutableOffset = reader.ReadInt32();
            stream.Position = checked(portableExecutableOffset + 4);
            return reader.ReadUInt16();
        }

        internal static bool TryDeleteDirectory(string directory)
        {
            const int attempts = 20;
            for (var attempt = 0; attempt < attempts; attempt++)
            {
                try
                {
                    if (Directory.Exists(directory))
                    {
                        Directory.Delete(directory, recursive: true);
                    }

                    return true;
                }
                catch (IOException)
                {
                    if (attempt + 1 < attempts)
                    {
                        Thread.Sleep(250);
                    }
                }
                catch (UnauthorizedAccessException)
                {
                    if (attempt + 1 < attempts)
                    {
                        Thread.Sleep(250);
                    }
                }
            }

            return false;
        }
    }
}

internal static partial class ControlledNativeMethods
{
    internal const ushort ImageFileMachineUnknown = 0;
    internal const uint SwpNoZOrder = 0x0004;
    internal const uint SwpNoActivate = 0x0010;
    internal const uint SwpShowWindow = 0x0040;
    internal const int SwMinimize = 6;
    internal const int SwRestore = 9;
    internal const uint WmClose = 0x0010;
    internal const uint WsPopup = 0x80000000;
    internal const int SmCmonitors = 80;
    internal const int GwlExStyle = -20;
    internal const long WsExNoActivate = 0x08000000L;

    [LibraryImport(
        "user32.dll",
        EntryPoint = "CreateWindowExW",
        SetLastError = true,
        StringMarshalling = StringMarshalling.Utf16)]
    internal static partial nint CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [LibraryImport("user32.dll", EntryPoint = "DestroyWindow", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool DestroyWindow(nint window);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowRect", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetWindowRect(nint window, out ControlledNativeRect rect);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowPos", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetWindowPos(
        nint window,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [LibraryImport("user32.dll", EntryPoint = "ShowWindow")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool ShowWindow(nint window, int command);

    [LibraryImport("user32.dll", EntryPoint = "IsWindowVisible")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool IsWindowVisible(nint window);

    [LibraryImport("user32.dll", EntryPoint = "IsIconic")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool IsIconic(nint window);

    [LibraryImport("user32.dll", EntryPoint = "SetForegroundWindow")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetForegroundWindow(nint window);

    [LibraryImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    internal static partial nint GetForegroundWindow();

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    internal static partial nint GetWindowLongPtr(nint window, int index);

    [LibraryImport("user32.dll", EntryPoint = "GetSystemMetrics")]
    internal static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll", EntryPoint = "GetDpiForWindow")]
    internal static partial int GetDpiForWindow(nint window);

    [LibraryImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool PostMessage(
        nint window,
        uint message,
        nint wordParameter,
        nint longParameter);

    [LibraryImport("kernel32.dll", EntryPoint = "IsWow64Process2", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool IsWow64Process2(
        nint process,
        out ushort processMachine,
        out ushort nativeMachine);
}

[StructLayout(LayoutKind.Sequential)]
internal struct ControlledNativeRect
{
    internal int Left;
    internal int Top;
    internal int Right;
    internal int Bottom;
}
