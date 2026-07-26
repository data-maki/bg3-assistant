using System.ComponentModel;
using BG3HonorAssistant.Windows.Interop;

namespace BG3HonorAssistant.Windows.GameDetection;

public sealed class Bg3WindowChangedEventArgs : EventArgs
{
    public Bg3WindowChangedEventArgs(Bg3WindowInfo? window)
    {
        Window = window;
    }

    public Bg3WindowInfo? Window { get; }
}

public sealed class Bg3WindowMonitor : IDisposable
{
    private static readonly TimeSpan RecoveryInterval = TimeSpan.FromSeconds(2);
    private readonly object sync = new();
    private readonly IBg3WindowLocator locator;
    private readonly WinEventCallback winEventCallback;
    private SynchronizationContext? synchronizationContext;
    private Timer? recoveryTimer;
    private nint foregroundHook;
    private nint locationHook;
    private bool disposed;

    public Bg3WindowMonitor(IBg3WindowLocator? locator = null)
    {
        this.locator = locator ?? new Bg3WindowLocator();
        winEventCallback = OnWinEvent;
    }

    public event EventHandler<Bg3WindowChangedEventArgs>? WindowChanged;

    public Bg3WindowInfo? Current { get; private set; }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        lock (sync)
        {
            if (recoveryTimer is not null)
            {
                return;
            }

            synchronizationContext ??= SynchronizationContext.Current;
            foregroundHook = CreateHook(NativeMethods.EventSystemForeground);
            try
            {
                locationHook = CreateHook(NativeMethods.EventObjectLocationChange);
                recoveryTimer = new Timer(
                    _ => Refresh(),
                    null,
                    TimeSpan.Zero,
                    RecoveryInterval);
            }
            catch
            {
                _ = NativeMethods.UnhookWinEvent(foregroundHook);
                foregroundHook = nint.Zero;
                throw;
            }
        }
    }

    public void Refresh()
    {
        if (disposed)
        {
            return;
        }

        Bg3WindowInfo? next;
        lock (sync)
        {
            if (disposed)
            {
                return;
            }

            next = locator.FindBestWindow();
            if (Equals(next, Current))
            {
                return;
            }

            Current = next;
        }

        Publish(next);
    }

    public void Dispose()
    {
        lock (sync)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            recoveryTimer?.Dispose();
            recoveryTimer = null;
            Unhook(ref locationHook);
            Unhook(ref foregroundHook);
        }
    }

    private nint CreateHook(uint eventType)
    {
        var hook = NativeMethods.SetWinEventHook(
            eventType,
            eventType,
            nint.Zero,
            winEventCallback,
            0,
            0,
            NativeMethods.WineventOutOfContext |
            NativeMethods.WineventSkipOwnProcess);
        if (hook == nint.Zero)
        {
            throw new Win32Exception();
        }

        return hook;
    }

    private void OnWinEvent(
        nint hook,
        uint eventType,
        nint window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime)
    {
        _ = hook;
        _ = window;
        _ = childId;
        _ = eventThread;
        _ = eventTime;

        if (eventType == NativeMethods.EventSystemForeground ||
            (eventType == NativeMethods.EventObjectLocationChange &&
             objectId == NativeMethods.ObjectIdWindow))
        {
            Refresh();
        }
    }

    private void Publish(Bg3WindowInfo? window)
    {
        var handler = WindowChanged;
        if (handler is null)
        {
            return;
        }

        var args = new Bg3WindowChangedEventArgs(window);
        if (synchronizationContext is null)
        {
            handler(this, args);
            return;
        }

        synchronizationContext.Post(
            state =>
            {
                if (!disposed)
                {
                    var (sender, callback, eventArgs) =
                        ((Bg3WindowMonitor, EventHandler<Bg3WindowChangedEventArgs>, Bg3WindowChangedEventArgs))state!;
                    callback(sender, eventArgs);
                }
            },
            (this, handler, args));
    }

    private static void Unhook(ref nint hook)
    {
        if (hook == nint.Zero)
        {
            return;
        }

        _ = NativeMethods.UnhookWinEvent(hook);
        hook = nint.Zero;
    }
}
