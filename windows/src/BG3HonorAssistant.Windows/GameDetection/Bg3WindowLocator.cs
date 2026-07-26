using System.IO;
using System.Runtime.InteropServices;
using BG3HonorAssistant.Windows.Interop;

namespace BG3HonorAssistant.Windows.GameDetection;

public interface IBg3WindowLocator
{
    Bg3WindowInfo? FindBestWindow();
}

public sealed class Bg3WindowLocator : IBg3WindowLocator
{
    public unsafe Bg3WindowInfo? FindBestWindow()
    {
        var context = new EnumerationContext();
        var contextHandle = GCHandle.Alloc(context);
        try
        {
            if (!NativeMethods.EnumWindows(
                    &InspectWindow,
                    GCHandle.ToIntPtr(contextHandle)))
            {
                var error = Marshal.GetLastPInvokeError();
                if (error != 0)
                {
                    throw new System.ComponentModel.Win32Exception(error);
                }
            }
        }
        finally
        {
            contextHandle.Free();
        }

        return context.Candidates
            .OrderByDescending(candidate => (long)candidate.Bounds.Width * candidate.Bounds.Height)
            .ThenBy(candidate => candidate.ProcessId)
            .FirstOrDefault();
    }

    [UnmanagedCallersOnly]
    private static int InspectWindow(nint window, nint parameter)
    {
        try
        {
            var context = (EnumerationContext)GCHandle
                .FromIntPtr(parameter)
                .Target!;
            if (!NativeMethods.IsWindowVisible(window) ||
                NativeMethods.IsIconic(window))
            {
                return 1;
            }

            _ = NativeMethods.GetWindowThreadProcessId(window, out var processId);
            if (processId == 0 ||
                !TryGetVerifiedProcessName(processId, out var processName))
            {
                return 1;
            }

            var bounds = GetBounds(window);
            if (!bounds.IsUsable)
            {
                return 1;
            }

            var dpi = NativeMethods.GetDpiForWindow(window);
            context.Candidates.Add(new Bg3WindowInfo(
                checked((int)processId),
                processName,
                window,
                bounds,
                dpi == 0 ? 96U : dpi));
        }
        catch
        {
            // Never allow a process exit, protected process, or malformed HWND to
            // escape across the unmanaged EnumWindows callback boundary.
        }

        return 1;
    }

    private static unsafe bool TryGetVerifiedProcessName(
        uint processId,
        out string processName)
    {
        processName = string.Empty;
        var process = NativeMethods.OpenProcess(
            NativeMethods.ProcessQueryLimitedInformation,
            inheritHandle: false,
            processId);
        if (process == nint.Zero)
        {
            return false;
        }

        try
        {
            const int maximumPath = 32768;
            Span<char> pathBuffer = stackalloc char[maximumPath];
            uint pathLength = maximumPath;
            fixed (char* pathPointer = pathBuffer)
            {
                if (!NativeMethods.QueryFullProcessImageName(
                        process,
                        0,
                        pathPointer,
                        ref pathLength))
                {
                    return false;
                }
            }

            var executablePath = new string(pathBuffer[..checked((int)pathLength)]);
            processName = Path.GetFileNameWithoutExtension(executablePath);
            return Bg3ProcessNames.IsSupported(processName);
        }
        finally
        {
            _ = NativeMethods.CloseHandle(process);
        }
    }

    private static WindowBounds GetBounds(nint window)
    {
        var size = Marshal.SizeOf<NativeRect>();
        if (NativeMethods.DwmGetWindowAttribute(
                window,
                NativeMethods.DwmwaExtendedFrameBounds,
                out var frame,
                size) != 0 &&
            !NativeMethods.GetWindowRect(window, out frame))
        {
            return default;
        }

        return new WindowBounds(frame.Left, frame.Top, frame.Right, frame.Bottom);
    }

    private sealed class EnumerationContext
    {
        internal List<Bg3WindowInfo> Candidates { get; } = [];
    }
}
