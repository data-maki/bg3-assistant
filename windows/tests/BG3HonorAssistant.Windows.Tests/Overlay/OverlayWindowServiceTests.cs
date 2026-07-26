using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Overlay;

namespace BG3HonorAssistant.Windows.Tests.Overlay;

public sealed class OverlayWindowServiceTests
{
    private const int ExtendedStyleIndex = -20;
    private const long ToolWindowStyle = 0x00000080L;
    private const long NoActivateStyle = 0x08000000L;
    private const uint PopupStyle = 0x80000000U;

    [Fact]
    public void ConfigureAppliesAndRemovesPassiveInputStyles()
    {
        using var window = TestWindow.Create();
        var service = new OverlayWindowService();

        service.Configure(window.Handle, passive: true);

        var passiveStyles = TestNativeMethods
            .GetWindowLongPtr(window.Handle, ExtendedStyleIndex)
            .ToInt64();
        Assert.Equal(
            ToolWindowStyle | NoActivateStyle,
            passiveStyles & (ToolWindowStyle | NoActivateStyle));

        service.SetPassive(window.Handle, passive: false);

        var interactiveStyles = TestNativeMethods
            .GetWindowLongPtr(window.Handle, ExtendedStyleIndex)
            .ToInt64();
        Assert.Equal(ToolWindowStyle, interactiveStyles & ToolWindowStyle);
        Assert.Equal(0, interactiveStyles & NoActivateStyle);
    }

    [Fact]
    public void ConfigureRejectsAnInvalidPointerSizedWindowHandle()
    {
        var service = new OverlayWindowService();

        var exception = Assert.Throws<Win32Exception>(
            () => service.Configure(new nint(0x1234), passive: true));

        Assert.Equal(1400, exception.NativeErrorCode);
    }

    [Fact]
    public void PositionRelativeToUsesPhysicalDpiCoordinatesWithoutTakingForeground()
    {
        using var window = TestWindow.Create();
        var service = new OverlayWindowService();
        service.Configure(window.Handle, passive: true);

        var foregroundBefore = TestNativeMethods.GetForegroundWindow();
        var gameBounds = new WindowBounds(-1700, 120, -100, 1020);
        var expected = OverlayPlacementCalculator.AtRightEdge(
            gameBounds,
            OverlayDpiCalculator.ToPhysicalPixels(320D, 144),
            OverlayDpiCalculator.ToPhysicalPixels(240D, 144));

        service.PositionRelativeTo(
            window.Handle,
            new Bg3WindowInfo(1, "bg3_dx11", new nint(1), gameBounds, 144),
            widthInDeviceIndependentPixels: 320,
            heightInDeviceIndependentPixels: 240);

        Assert.True(TestNativeMethods.GetWindowRect(window.Handle, out var actual));
        Assert.Equal(expected.X, actual.Left);
        Assert.Equal(expected.Y, actual.Top);
        Assert.Equal(expected.Width, actual.Right - actual.Left);
        Assert.Equal(expected.Height, actual.Bottom - actual.Top);
        Assert.Equal(foregroundBefore, TestNativeMethods.GetForegroundWindow());
    }

    [Fact]
    public void PositionAtRightEdgePreservesWpfOwnedPhysicalSizeAndForeground()
    {
        using var window = TestWindow.Create();
        var service = new OverlayWindowService();
        service.Configure(window.Handle, passive: true);
        var foregroundBefore = TestNativeMethods.GetForegroundWindow();
        var gameBounds = new WindowBounds(-300, 100, 900, 800);
        var expected = OverlayPlacementCalculator.AtRightEdge(
            gameBounds,
            100,
            100);

        service.PositionAtRightEdge(
            window.Handle,
            new Bg3WindowInfo(1, "bg3", new nint(1), gameBounds, 96));

        Assert.True(TestNativeMethods.GetWindowRect(window.Handle, out var actual));
        Assert.Equal(expected.X, actual.Left);
        Assert.Equal(expected.Y, actual.Top);
        Assert.Equal(100, actual.Right - actual.Left);
        Assert.Equal(100, actual.Bottom - actual.Top);
        Assert.Equal(foregroundBefore, TestNativeMethods.GetForegroundWindow());
    }

    [Fact]
    public async Task WpfWindowBecomesTopmostAndPassiveWithoutTakingForeground()
    {
        var completion =
            new TaskCompletionSource<(long Styles, nint ForegroundBefore, nint ForegroundAfter)>(
                TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                var foregroundBefore = TestNativeMethods.GetForegroundWindow();
                var window = new Window
                {
                    Width = 240,
                    Height = 160,
                    WindowStyle = WindowStyle.None,
                    ShowInTaskbar = false
                };
                nint handle = nint.Zero;
                window.SourceInitialized += (_, _) =>
                {
                    handle = new WindowInteropHelper(window).Handle;
                    new OverlayWindowService().Configure(handle, passive: true);
                };
                window.Show();
                window.Dispatcher.Invoke(
                    () => { },
                    DispatcherPriority.ApplicationIdle);
                var styles = TestNativeMethods
                    .GetWindowLongPtr(handle, ExtendedStyleIndex)
                    .ToInt64();
                var foregroundAfter = TestNativeMethods.GetForegroundWindow();
                window.Close();
                completion.TrySetResult((styles, foregroundBefore, foregroundAfter));
            }
            catch (Exception exception)
            {
                completion.TrySetException(exception);
            }
        })
        {
            IsBackground = true,
            Name = "BG3 overlay WPF HWND test"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        var result = await completion.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(
            (result.Styles & ToolWindowStyle) != 0,
            $"Expected WS_EX_TOOLWINDOW in 0x{result.Styles:X}.");
        Assert.True(
            (result.Styles & 0x00000008L) != 0,
            $"Expected WS_EX_TOPMOST in 0x{result.Styles:X}.");
        Assert.True(
            (result.Styles & NoActivateStyle) != 0,
            $"Expected WS_EX_NOACTIVATE in 0x{result.Styles:X}.");
        Assert.Equal(result.ForegroundBefore, result.ForegroundAfter);
    }

    private sealed class TestWindow : IDisposable
    {
        private TestWindow(nint handle)
        {
            Handle = handle;
        }

        public nint Handle { get; }

        public static TestWindow Create()
        {
            var handle = TestNativeMethods.CreateWindowEx(
                0,
                "STATIC",
                "BG3 Honor Assistant test window",
                PopupStyle,
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

            return new TestWindow(handle);
        }

        public void Dispose()
        {
            if (!TestNativeMethods.DestroyWindow(Handle))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }
        }
    }
}

[StructLayout(LayoutKind.Sequential)]
internal struct TestNativeRect
{
    internal int Left;
    internal int Top;
    internal int Right;
    internal int Bottom;
}

internal static partial class TestNativeMethods
{
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

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    internal static partial nint GetWindowLongPtr(nint window, int index);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowRect", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetWindowRect(nint window, out TestNativeRect rect);

    [LibraryImport("user32.dll", EntryPoint = "GetDpiForWindow")]
    internal static partial uint GetDpiForWindow(nint window);

    [LibraryImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    internal static partial nint GetForegroundWindow();

}
