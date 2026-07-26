using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Overlay;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Windows.Overlay;
using WpfMouseEventArgs = System.Windows.Input.MouseEventArgs;

namespace BG3HonorAssistant.App;

public partial class OverlayWindow : Window
{
    private readonly OverlayWindowService windowService;
    private readonly DispatcherTimer petTimer;
    private nint handle;
    private DateTimeOffset? petHoverStarted;
    private DateTimeOffset? petAttentionStarted;
    private PetPoint? petPointer;
    private bool reduceMotion;
    private string? lastGoalTitle;

    public OverlayWindow(OverlayWindowService windowService)
    {
        this.windowService = windowService;
        InitializeComponent();
        petTimer = new DispatcherTimer(
            TimeSpan.FromMilliseconds(1000D / 30D),
            DispatcherPriority.Render,
            OnPetTimerTick,
            Dispatcher);
        Closed += (_, _) => petTimer.Stop();
        UpdatePetFrame();
    }

    public event EventHandler? OpenPlannerRequested;

    public event EventHandler? CollapseRequested;

    public event EventHandler? OpenRouteRequested;

    public event EventHandler? OpenChatRequested;

    public event EventHandler? TaskDoneRequested;

    public event EventHandler? SnoozeRequested;

    public event EventHandler? MuteRequested;

    public event EventHandler? PinRequested;

    public event EventHandler<OverlayDensityChangedEventArgs>? DensityRequested;

    public event EventHandler? MovedByUser;

    public nint NativeHandle => handle;

    public void Update(CurrentGoalPresentation goal, AppPreferences preferences)
    {
        var density = preferences.OverlayDensity;
        GoalText.Text = goal.Title;
        AreaText.Text = string.IsNullOrWhiteSpace(goal.Area)
            ? goal.Danger.ToUpperInvariant()
            : $"{goal.Area} - {goal.Danger.ToUpperInvariant()}";
        LevelText.Text = $"L{goal.MinimumLevel}+";
        AvoidText.Text = goal.Avoid;
        ReferenceGoalText.Text = goal.Title;
        ReferenceMetaText.Text =
            $"{goal.Area} · L{goal.MinimumLevel}+ · {goal.Danger.ToUpperInvariant()}";
        ReferenceAvoidText.Text = goal.Avoid;

        MinimalPanel.Visibility =
            density == OverlayDensity.Minimal ? Visibility.Visible : Visibility.Collapsed;
        FocusPanel.Visibility =
            density == OverlayDensity.Focus ? Visibility.Visible : Visibility.Collapsed;
        ReferencePanel.Visibility =
            density == OverlayDensity.Reference ? Visibility.Visible : Visibility.Collapsed;
        (Width, Height) = density switch
        {
            OverlayDensity.Minimal => (92, 92),
            OverlayDensity.Reference => (390, 290),
            _ => (340, 190),
        };

        reduceMotion =
            preferences.ReducedMotion ||
            !SystemParameters.ClientAreaAnimation;
        if (density == OverlayDensity.Minimal &&
            !string.Equals(lastGoalTitle, goal.Title, StringComparison.Ordinal) &&
            !reduceMotion)
        {
            petAttentionStarted = DateTimeOffset.UtcNow;
            EnsurePetTimer();
        }

        lastGoalTitle = goal.Title;
        UpdatePetFrame();
    }

    public void EnsurePassive()
    {
        if (handle != nint.Zero)
        {
            windowService.SetPassive(handle, passive: true);
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        handle = new WindowInteropHelper(this).Handle;
        windowService.Configure(handle, passive: true);
    }

    private void OnDeactivated(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        EnsurePassive();
    }

    private void OnOpenPlannerClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (handle != nint.Zero)
        {
            windowService.SetPassive(handle, passive: false);
        }

        OpenPlannerRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnCollapseClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        CollapseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnOpenRouteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        OpenRouteRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnOpenChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        OpenChatRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnTaskDoneClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        TaskDoneRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnSnoozeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        SnoozeRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnMuteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        MuteRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPinClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        PinRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnMinimalDensityClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        DensityRequested?.Invoke(
            this,
            new OverlayDensityChangedEventArgs(OverlayDensity.Minimal));
    }

    private void OnFocusDensityClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        DensityRequested?.Invoke(
            this,
            new OverlayDensityChangedEventArgs(OverlayDensity.Focus));
    }

    private void OnReferenceDensityClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        DensityRequested?.Invoke(
            this,
            new OverlayDensityChangedEventArgs(OverlayDensity.Reference));
    }

    private void OnPetMouseEnter(object sender, WpfMouseEventArgs eventArgs)
    {
        _ = sender;
        petHoverStarted ??= DateTimeOffset.UtcNow;
        UpdatePetPointer(eventArgs);
        EnsurePetTimer();
        UpdatePetFrame();
    }

    private void OnPetMouseMove(object sender, WpfMouseEventArgs eventArgs)
    {
        _ = sender;
        UpdatePetPointer(eventArgs);
        UpdatePetFrame();
    }

    private void OnPetMouseLeave(object sender, WpfMouseEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        petHoverStarted = null;
        petPointer = null;
        UpdatePetFrame();
    }

    private void OnPetTimerTick(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (petAttentionStarted is { } attention &&
            DateTimeOffset.UtcNow - attention >= TimeSpan.FromSeconds(2.4))
        {
            petAttentionStarted = null;
        }

        UpdatePetFrame();
        if (petHoverStarted is null && petAttentionStarted is null)
        {
            petTimer.Stop();
        }
    }

    private void UpdatePetPointer(WpfMouseEventArgs eventArgs)
    {
        var point = eventArgs.GetPosition(MinimalPanel);
        petPointer = new PetPoint(point.X, point.Y);
    }

    private void EnsurePetTimer()
    {
        if (!reduceMotion && !petTimer.IsEnabled)
        {
            petTimer.Start();
        }
    }

    private void UpdatePetFrame()
    {
        var started = petHoverStarted ?? petAttentionStarted;
        var pointer = petHoverStarted is null && petAttentionStarted is not null
            ? new PetPoint(
                Math.Max(1D, PetImage.ActualWidth) * 1.3D,
                Math.Max(1D, PetImage.ActualHeight) * 0.45D)
            : petPointer;
        var frame = PetAnimationModel.Frame(
            isHovered: started is not null,
            hoverElapsed: started is null
                ? TimeSpan.Zero
                : DateTimeOffset.UtcNow - started.Value,
            pointer,
            new PetSize(
                Math.Max(1D, PetImage.ActualWidth > 0D ? PetImage.ActualWidth : 62D),
                Math.Max(1D, PetImage.ActualHeight > 0D ? PetImage.ActualHeight : 67D)),
            reduceMotion);
        PetImage.Source = PetSpriteLoader.Frame(frame);
        PetImage.Visibility =
            PetImage.Source is null ? Visibility.Collapsed : Visibility.Visible;
        PetFallbackText.Visibility =
            PetImage.Source is null ? Visibility.Visible : Visibility.Collapsed;
        System.Windows.Automation.AutomationProperties.SetItemStatus(
            PetImage,
            started is null ? "Resting" : "Awake");
    }

    private void OnDragMouseLeftButtonDown(
        object sender,
        MouseButtonEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.ChangedButton != MouseButton.Left ||
            eventArgs.OriginalSource is not DependencyObject source ||
            FindVisualParent<System.Windows.Controls.Primitives.ButtonBase>(source) is not null)
        {
            return;
        }

        try
        {
            DragMove();
            MovedByUser?.Invoke(this, EventArgs.Empty);
        }
        finally
        {
            EnsurePassive();
        }
    }

    private static T? FindVisualParent<T>(DependencyObject? current)
        where T : DependencyObject
    {
        while (current is not null)
        {
            if (current is T match)
            {
                return match;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return null;
    }
}
