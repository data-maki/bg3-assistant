using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Overlay;

namespace OverlayHarness;

public partial class MainWindow : Window
{
    private readonly Bg3WindowMonitor gameMonitor = new();
    private readonly OverlayWindowService overlayWindow = new();
    private nint handle;

    public MainWindow()
    {
        InitializeComponent();
        gameMonitor.WindowChanged += (_, eventArgs) => Follow(eventArgs.Window);
        Closed += (_, _) => gameMonitor.Dispose();
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        handle = new WindowInteropHelper(this).Handle;
        overlayWindow.Configure(handle, passive: true);
        gameMonitor.Start();
    }

    private void OnLocateClick(object sender, RoutedEventArgs eventArgs)
    {
        gameMonitor.Refresh();
    }

    private void Follow(Bg3WindowInfo? game)
    {
        if (handle == nint.Zero)
        {
            return;
        }

        if (game is null)
        {
            StatusText.Text =
                "BG3 not detected. Start the Vulkan or DirectX 11 executable in Windowed or Borderless Windowed mode.";
            DpiText.Text = "DPI: overlay active";
            return;
        }

        overlayWindow.PositionRelativeTo(handle, game, Width, Height);
        StatusText.Text =
            $"{game.ProcessName}.exe · PID {game.ProcessId} · " +
            $"{game.Bounds.Width}×{game.Bounds.Height} at " +
            $"({game.Bounds.Left},{game.Bounds.Top})";
        DpiText.Text = $"Game DPI: {game.Dpi}";
    }

    private void OnProbePreviewMouseDown(object sender, MouseButtonEventArgs eventArgs)
    {
        overlayWindow.SetPassive(handle, passive: false);
        _ = Activate();
        _ = ActivationProbe.Focus();
    }

    private void OnProbeGotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs eventArgs)
    {
        StatusText.Text = "Text activation enabled deliberately. Gameplay should regain focus when editing ends.";
    }

    private void OnProbeLostKeyboardFocus(object sender, KeyboardFocusChangedEventArgs eventArgs)
    {
        overlayWindow.SetPassive(handle, passive: true);
        if (gameMonitor.Current is not null)
        {
            overlayWindow.PositionRelativeTo(handle, gameMonitor.Current, Width, Height);
        }
    }

    private void OnWindowMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs)
    {
        if (eventArgs.ButtonState == MouseButtonState.Pressed &&
            !ActivationProbe.IsKeyboardFocused)
        {
            DragMove();
        }
    }
}
