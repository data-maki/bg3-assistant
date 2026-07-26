using System.Windows;
using System.Windows.Interop;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Overlay;

namespace BG3HonorAssistant.App;

public sealed class OverlayDensityChangedEventArgs(OverlayDensity density) : EventArgs
{
    public OverlayDensity Density { get; } = density;
}

public sealed class OverlayAnchorChangedEventArgs(OverlayAnchor anchor) : EventArgs
{
    public OverlayAnchor Anchor { get; } = anchor;
}

public sealed class OverlayCoordinator : IDisposable
{
    private readonly Bg3WindowMonitor monitor;
    private readonly OverlayWindowService windowService;
    private readonly OverlayWindow window;
    private CurrentGoalPresentation? goal;
    private AppPreferences preferences = new();
    private bool forcedPreview;
    private bool disposed;

    public OverlayCoordinator(
        Bg3WindowMonitor? monitor = null,
        OverlayWindowService? windowService = null)
    {
        this.monitor = monitor ?? new Bg3WindowMonitor();
        this.windowService = windowService ?? new OverlayWindowService();
        window = new OverlayWindow(this.windowService);
        window.OpenPlannerRequested += (_, _) => OpenPlannerRequested?.Invoke(this, EventArgs.Empty);
        window.CollapseRequested += (_, _) => Collapse();
        window.OpenRouteRequested += (_, _) => OpenRouteRequested?.Invoke(this, EventArgs.Empty);
        window.OpenChatRequested += (_, _) => OpenChatRequested?.Invoke(this, EventArgs.Empty);
        window.TaskDoneRequested += (_, _) => TaskDoneRequested?.Invoke(this, EventArgs.Empty);
        window.SnoozeRequested += (_, _) => SnoozeRequested?.Invoke(this, EventArgs.Empty);
        window.MuteRequested += (_, _) => MuteRequested?.Invoke(this, EventArgs.Empty);
        window.PinRequested += (_, _) => PinRequested?.Invoke(this, EventArgs.Empty);
        window.DensityRequested += (_, change) => SetDensity(change.Density);
        window.MovedByUser += OnWindowMovedByUser;
        this.monitor.WindowChanged += OnWindowChanged;
    }

    public event EventHandler? StateChanged;

    public event EventHandler? OpenPlannerRequested;

    public event EventHandler? OpenRouteRequested;

    public event EventHandler? OpenChatRequested;

    public event EventHandler? TaskDoneRequested;

    public event EventHandler? SnoozeRequested;

    public event EventHandler? MuteRequested;

    public event EventHandler? PinRequested;

    public event EventHandler<OverlayDensityChangedEventArgs>? DensityChanged;

    public event EventHandler<OverlayAnchorChangedEventArgs>? AnchorChanged;

    public Bg3WindowInfo? GameWindow => monitor.Current;

    public bool IsVisible => window.IsVisible;

    public string GameStatus => GameWindow is null
        ? "waiting for bg3.exe or bg3_dx11.exe"
        : $"{GameWindow.ProcessName}.exe detected at {GameWindow.Dpi * 100 / 96}% DPI";

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        monitor.Start();
    }

    public void Update(CurrentGoalPresentation presentation, AppPreferences nextPreferences)
    {
        goal = presentation;
        preferences = nextPreferences;
        window.Update(presentation, preferences);
        if (GameWindow is not null && preferences.ShowOverlayWhileGameRuns)
        {
            ShowAtGame();
        }
        else if (!forcedPreview)
        {
            window.Hide();
        }
    }

    public void ShowPreview()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        forcedPreview = true;
        if (goal is not null)
        {
            window.Update(goal, preferences);
        }

        if (GameWindow is not null)
        {
            ShowAtGame();
            return;
        }

        if (!window.IsVisible)
        {
            window.Show();
        }

        PositionPreview();
        window.EnsurePassive();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Hide()
    {
        forcedPreview = false;
        window.Hide();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        monitor.WindowChanged -= OnWindowChanged;
        window.MovedByUser -= OnWindowMovedByUser;
        monitor.Dispose();
        window.Close();
    }

    private void Collapse()
    {
        SetDensity(OverlayDensity.Minimal);
    }

    private void SetDensity(OverlayDensity density)
    {
        preferences = preferences with { OverlayDensity = density };
        DensityChanged?.Invoke(
            this,
            new OverlayDensityChangedEventArgs(density));
        if (goal is not null)
        {
            window.Update(goal, preferences);
        }

        if (GameWindow is not null)
        {
            ShowAtGame();
        }
        else
        {
            ShowPreview();
        }
    }

    private void OnWindowChanged(object? sender, Bg3WindowChangedEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.Window is not null &&
            preferences.ShowOverlayWhileGameRuns)
        {
            ShowAtGame();
        }
        else if (!forcedPreview)
        {
            window.Hide();
        }

        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void ShowAtGame()
    {
        if (GameWindow is not { } game)
        {
            return;
        }

        if (!window.IsVisible)
        {
            window.Show();
        }

        var handle = new WindowInteropHelper(window).Handle;
        windowService.PositionAtAnchor(handle, game, SavedAnchor());
        window.Dispatcher.BeginInvoke(
            () =>
            {
                if (!disposed && GameWindow is not null && window.IsVisible)
                {
                    windowService.PositionAtAnchor(
                        handle,
                        GameWindow,
                        SavedAnchor());
                }
            });
        window.EnsurePassive();
    }

    private void OnWindowMovedByUser(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var anchor = GameWindow is { } game
            ? windowService.ReadNormalizedAnchor(window.NativeHandle, game)
            : ReadPreviewAnchor();
        preferences = preferences with
        {
            OverlayAnchorX = anchor.X,
            OverlayAnchorY = anchor.Y,
        };
        AnchorChanged?.Invoke(this, new OverlayAnchorChangedEventArgs(anchor));

        if (GameWindow is { } current)
        {
            windowService.PositionAtAnchor(window.NativeHandle, current, anchor);
        }
        else
        {
            PositionPreview();
        }
    }

    private OverlayAnchor? SavedAnchor()
    {
        return preferences.OverlayAnchorX is { } x &&
               preferences.OverlayAnchorY is { } y
            ? new OverlayAnchor(x, y)
            : null;
    }

    private void PositionPreview()
    {
        var work = SystemParameters.WorkArea;
        var freeWidth = Math.Max(0D, work.Width - window.Width);
        var freeHeight = Math.Max(0D, work.Height - window.Height);
        var saved = SavedAnchor();
        var anchorX = Math.Clamp(
            saved?.X ?? (freeWidth <= 0D ? 0D : (freeWidth - 24D) / freeWidth),
            0D,
            1D);
        var anchorY = Math.Clamp(saved?.Y ?? 0.3D, 0D, 1D);
        window.Left = work.Left + anchorX * freeWidth;
        window.Top = work.Top + anchorY * freeHeight;
    }

    private OverlayAnchor ReadPreviewAnchor()
    {
        var work = SystemParameters.WorkArea;
        var freeWidth = Math.Max(1D, work.Width - window.Width);
        var freeHeight = Math.Max(1D, work.Height - window.Height);
        return new OverlayAnchor(
            Math.Clamp((window.Left - work.Left) / freeWidth, 0D, 1D),
            Math.Clamp((window.Top - work.Top) / freeHeight, 0D, 1D));
    }
}
