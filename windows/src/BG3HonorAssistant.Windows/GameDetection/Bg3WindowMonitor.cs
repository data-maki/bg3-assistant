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
    private uint hookThreadId;
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

            if (foregroundHook != nint.Zero || locationHook != nint.Zero)
            {
                throw new InvalidOperationException(
                    "WinEvent hook cleanup must complete before the monitor can restart.");
            }

            synchronizationContext ??= SynchronizationContext.Current;
            hookThreadId = NativeMethods.GetCurrentThreadId();
            try
            {
                foregroundHook = CreateHook(NativeMethods.EventSystemForeground);
                locationHook = CreateHook(NativeMethods.EventObjectLocationChange);
                recoveryTimer = new Timer(
                    _ => Refresh(),
                    null,
                    TimeSpan.Zero,
                    RecoveryInterval);
            }
            catch (Exception startException)
            {
                recoveryTimer?.Dispose();
                recoveryTimer = null;
                var cleanupErrors = UnhookAll();
                if (cleanupErrors.Count == 0)
                {
                    hookThreadId = 0;
                    throw;
                }

                throw new AggregateException(
                    "WinEvent hook startup failed and cleanup was incomplete.",
                    [startException, .. cleanupErrors]);
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

            if (hookThreadId != 0 &&
                hookThreadId != NativeMethods.GetCurrentThreadId())
            {
                throw new InvalidOperationException(
                    "Bg3WindowMonitor must be disposed on the OS thread that called Start.");
            }

            recoveryTimer?.Dispose();
            recoveryTimer = null;
            var cleanupErrors = UnhookAll();
            if (cleanupErrors.Count > 0)
            {
                throw new AggregateException(
                    "One or more WinEvent hooks could not be removed.",
                    cleanupErrors);
            }

            hookThreadId = 0;
            disposed = true;
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

    private List<Exception> UnhookAll()
    {
        var errors = new List<Exception>(capacity: 2);
        Unhook(ref locationHook, errors);
        Unhook(ref foregroundHook, errors);
        return errors;
    }

    private static void Unhook(
        ref nint hook,
        ICollection<Exception> errors)
    {
        if (hook == nint.Zero)
        {
            return;
        }

        if (NativeMethods.UnhookWinEvent(hook))
        {
            hook = nint.Zero;
            return;
        }

        errors.Add(new Win32Exception());
    }
}
