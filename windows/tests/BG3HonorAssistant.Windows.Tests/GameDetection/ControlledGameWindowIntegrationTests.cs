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
    private static readonly TimeSpan OperationTimeout = TimeSpan.FromSeconds(10);
    private readonly ITestOutputHelper output;

    public ControlledGameWindowIntegrationTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Theory]
    [InlineData("bg3", true)]
    [InlineData("bg3_dx11", false)]
    public void ExactNameX64HostExercisesDetectionFollowingAndLifecycle(
        string processName,
        bool borderless)
    {
        using var host = ControlledGameHost.Start(processName, borderless);
        Assert.Equal(ControlledGameHost.Amd64Machine, host.PortableExecutableMachine);
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
        Assert.True(ControlledNativeMethods.SetForegroundWindow(overlay.Handle));
        WaitFor(() => ControlledNativeMethods.GetForegroundWindow() == overlay.Handle);

        overlayService.SetPassive(overlay.Handle, passive: true);
        var passiveStyles = ControlledNativeMethods
            .GetWindowLongPtr(overlay.Handle, ControlledNativeMethods.GwlExStyle)
            .ToInt64();
        Assert.NotEqual(0, passiveStyles & ControlledNativeMethods.WsExNoActivate);
        _ = ControlledNativeMethods.SetForegroundWindow(host.WindowHandle);
        WaitFor(() => ControlledNativeMethods.GetForegroundWindow() == host.WindowHandle);
        foregroundBefore = ControlledNativeMethods.GetForegroundWindow();

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

        Assert.Contains(observed, candidate => candidate?.Bounds == moved.Bounds);
        Assert.Contains(observed, candidate => candidate is null);
        Assert.Contains(observed, candidate => candidate?.Bounds == restored.Bounds);

        output.WriteLine(
            "host={0}.exe; mode={1}; pe=0x{2:X4}; pid={3}; initial={4}; moved={5}; restored={6}; dpi={7}; monitors={8}; os={9}; test-process={10}",
            processName,
            borderless ? "borderless-style" : "windowed-style",
            host.PortableExecutableMachine,
            host.Process.Id,
            initial.Bounds,
            moved.Bounds,
            restored.Bounds,
            restored.Dpi,
            ControlledNativeMethods.GetSystemMetrics(ControlledNativeMethods.SmCmonitors),
            Environment.OSVersion.VersionString,
            RuntimeInformation.ProcessArchitecture);
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
            ushort portableExecutableMachine)
        {
            StagingDirectory = stagingDirectory;
            Process = process;
            WindowHandle = windowHandle;
            PortableExecutableMachine = portableExecutableMachine;
        }

        internal const ushort Amd64Machine = 0x8664;

        private string StagingDirectory { get; }

        internal Process Process { get; }

        internal nint WindowHandle { get; }

        internal ushort PortableExecutableMachine { get; }

        internal static ControlledGameHost Start(string processName, bool borderless)
        {
            var sourceDirectory = FindHostOutput();
            var portableExecutableMachine = ReadPortableExecutableMachine(
                Path.Combine(sourceDirectory, "GameWindowHost.exe"));
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

            var executablePath = Path.Combine(stagingDirectory, $"{processName}.exe");
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
                    portableExecutableMachine);
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

        private static string FindHostOutput()
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
                    var output = Path.Combine(
                        directory.FullName,
                        "spikes",
                        "GameWindowHost",
                        "bin",
                        configuration,
                        "net10.0-windows10.0.26100.0",
                        "win-x64");
                    if (File.Exists(Path.Combine(output, "GameWindowHost.exe")))
                    {
                        return output;
                    }

                    throw new FileNotFoundException(
                        "Build GameWindowHost before running the controlled-window tests.",
                        Path.Combine(output, "GameWindowHost.exe"));
                }

                directory = directory.Parent;
            }

            throw new DirectoryNotFoundException(
                "Could not locate the Windows solution root for GameWindowHost.");
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

        private static bool TryDeleteDirectory(string directory)
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
}

[StructLayout(LayoutKind.Sequential)]
internal struct ControlledNativeRect
{
    internal int Left;
    internal int Top;
    internal int Right;
    internal int Bottom;
}
