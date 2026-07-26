using System.IO;
using System.Windows;
using System.Windows.Interop;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;
using BG3HonorAssistant.Windows.Credentials;
using BG3HonorAssistant.Windows.Overlay;
using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Shell;
using BG3HonorAssistant.Windows.SingleInstance;
using BG3HonorAssistant.Windows.Startup;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class App : System.Windows.Application
{
    private SingleInstanceService? singleInstance;
    private System.Windows.Forms.NotifyIcon? trayIcon;
    private TrayMenu? trayMenu;
    private OverlayCoordinator? overlay;
    private AssistantController? controller;
    private MainWindow? plannerWindow;
    private bool trayNoticeShown;

    public bool ExitRequested { get; private set; }

    protected override async void OnStartup(StartupEventArgs eventArgs)
    {
        OverlayWindowService.EnablePerMonitorV2DpiAwareness();
        base.OnStartup(eventArgs);
        ApplyAccessibilityTheme();
        SystemParameters.StaticPropertyChanged += OnSystemParametersChanged;

        try
        {
            singleInstance = new SingleInstanceService();
            if (!singleInstance.IsPrimary)
            {
                _ = singleInstance.NotifyExistingInstance();
                singleInstance.Dispose();
                singleInstance = null;
                Shutdown();
                return;
            }

            var paths = AppDataPaths.Current();
            var openRouter = new OpenRouterClient(AssistantHttpClient.Instance);
            controller = new AssistantController(
                new RunRepository(paths.Database),
                new GuideRepository());
            var guidePath = Path.Combine(
                AppContext.BaseDirectory,
                "Resources",
                "Data",
                "guide-bundle.json");
            await controller.InitializeAsync(guidePath);

            overlay = new OverlayCoordinator();
            var launcher = new GameLauncher();
            var window = new MainWindow(
                controller,
                new StartupTaskService(),
                launcher,
                paths,
                overlay,
                new CredentialStore(),
                openRouter,
                new BuildImportCoordinator(
                    new SecureBuildSourceLoader(AssistantHttpClient.Instance),
                    openRouter));
            plannerWindow = window;
            MainWindow = window;
            overlay.OpenPlannerRequested += (_, _) => ShowMainWindow();
            overlay.DensityChanged += async (_, change) =>
                await controller.UpdatePreferencesAsync(
                    controller.Preferences with
                    {
                        OverlayDensity = change.Density,
                    });
            overlay.AnchorChanged += async (_, change) =>
                await controller.UpdatePreferencesAsync(
                    controller.Preferences with
                    {
                        OverlayAnchorX = change.Anchor.X,
                        OverlayAnchorY = change.Anchor.Y,
                    });
            window.SourceInitialized += (_, _) => AttachActivationHook(window);
            CreateTrayIcon();
            overlay.Start();
            window.Show();
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                $"BG3 Honor Assistant could not start.\n\n{exception.Message}",
                "BG3 Honor Assistant",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            ExitRequested = true;
            Shutdown();
        }
    }

    public void ShowMainWindow()
    {
        if (plannerWindow is null)
        {
            return;
        }

        plannerWindow.Show();
        if (plannerWindow.WindowState == WindowState.Minimized)
        {
            plannerWindow.WindowState = WindowState.Normal;
        }

        plannerWindow.Activate();
        plannerWindow.Topmost = true;
        plannerWindow.Topmost = false;
        plannerWindow.Focus();
    }

    public void ShowTrayNotice()
    {
        if (trayNoticeShown || trayIcon is null)
        {
            return;
        }

        trayNoticeShown = true;
        trayIcon.BalloonTipTitle = "BG3 Honor Assistant is still running";
        trayIcon.BalloonTipText =
            "Use the tray icon to reopen the planner or exit.";
        trayIcon.ShowBalloonTip(4000);
    }

    public void ExitApplication()
    {
        if (ExitRequested)
        {
            return;
        }

        ExitRequested = true;
        overlay?.Dispose();
        overlay = null;
        trayIcon?.Dispose();
        trayIcon = null;
        trayMenu?.Dispose();
        trayMenu = null;
        singleInstance?.Dispose();
        singleInstance = null;
        plannerWindow?.Close();
        plannerWindow = null;
        controller = null;
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs eventArgs)
    {
        SystemParameters.StaticPropertyChanged -= OnSystemParametersChanged;
        overlay?.Dispose();
        trayIcon?.Dispose();
        trayMenu?.Dispose();
        singleInstance?.Dispose();
        base.OnExit(eventArgs);
    }

    private void OnSystemParametersChanged(
        object? sender,
        System.ComponentModel.PropertyChangedEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.PropertyName == nameof(SystemParameters.HighContrast))
        {
            ApplyAccessibilityTheme();
        }
    }

    private void ApplyAccessibilityTheme()
    {
        if (SystemParameters.HighContrast)
        {
            Resources["WindowBackgroundBrush"] = System.Windows.SystemColors.WindowBrush;
            Resources["PanelBrush"] = System.Windows.SystemColors.ControlBrush;
            Resources["PanelRaisedBrush"] = System.Windows.SystemColors.ControlBrush;
            Resources["AccentBrush"] = System.Windows.SystemColors.HighlightBrush;
            Resources["PrimaryTextBrush"] = System.Windows.SystemColors.WindowTextBrush;
            Resources["SecondaryTextBrush"] = System.Windows.SystemColors.GrayTextBrush;
            Resources["DangerBrush"] = System.Windows.SystemColors.HotTrackBrush;
            return;
        }

        Resources["WindowBackgroundBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0x11, 0x13, 0x1A));
        Resources["PanelBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0x1B, 0x1E, 0x28));
        Resources["PanelRaisedBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0x24, 0x28, 0x36));
        Resources["AccentBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0xD5, 0xA6, 0x4C));
        Resources["PrimaryTextBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0xF4, 0xF0, 0xE8));
        Resources["SecondaryTextBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0xBB, 0xB5, 0xAA));
        Resources["DangerBrush"] =
            new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromRgb(0xE1, 0x70, 0x70));
    }

    private void AttachActivationHook(Window window)
    {
        var source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
        source?.AddHook(
            (nint hwnd, int message, nint word, nint data, ref bool handled) =>
            {
                _ = hwnd;
                _ = word;
                _ = data;
                if (singleInstance is not null &&
                    unchecked((uint)message) == singleInstance.ActivationMessage)
                {
                    ShowMainWindow();
                    handled = true;
                }

                return nint.Zero;
            });
    }

    private void CreateTrayIcon()
    {
        trayMenu = new TrayMenu(
            new TrayMenuActions(
                ShowOverlay: () => InvokeOnDispatcher(() => overlay?.ShowPreview()),
                OpenPlanner: () => InvokeOnDispatcher(
                    () =>
                    {
                        ShowMainWindow();
                        plannerWindow?.ShowNow();
                    }),
                OpenMap: () => InvokeOnDispatcher(
                    () => plannerWindow?.OpenCurrentActMap()),
                SwitchRun: runId => InvokeOnDispatcher(
                    async () =>
                    {
                        if (plannerWindow is not null)
                        {
                            await plannerWindow.SwitchRunFromTrayAsync(runId);
                        }
                    }),
                LaunchGame: () => InvokeOnDispatcher(() => plannerWindow?.LaunchGame()),
                TogglePet: () => InvokeOnDispatcher(TogglePet),
                OpenSettings: () => InvokeOnDispatcher(
                    () =>
                    {
                        ShowMainWindow();
                        plannerWindow?.ShowSettings();
                    }),
                Quit: () => InvokeOnDispatcher(ExitApplication)));
        trayMenu.Menu.Opening += (_, _) => InvokeOnDispatcher(RefreshTrayMenu);

        trayIcon = new System.Windows.Forms.NotifyIcon
        {
            Text = "BG3 Honor Assistant",
            Icon = System.Drawing.SystemIcons.Application,
            ContextMenuStrip = trayMenu.Menu,
            Visible = true,
        };
        trayIcon.DoubleClick += (_, _) => InvokeOnDispatcher(ShowMainWindow);
    }

    private void RefreshTrayMenu()
    {
        if (trayMenu is null || controller is null)
        {
            return;
        }

        trayMenu.Refresh(
            controller.Run.Name ?? "Honor Run",
            controller.Runs,
            overlay?.IsVisible == true);
    }

    private void TogglePet()
    {
        if (overlay?.IsVisible == true)
        {
            overlay.Hide();
        }
        else
        {
            overlay?.ShowPreview();
        }
    }

    private void InvokeOnDispatcher(Action action)
    {
        if (Dispatcher.CheckAccess())
        {
            action();
        }
        else
        {
            Dispatcher.Invoke(action);
        }
    }

    private void InvokeOnDispatcher(Func<Task> action)
    {
        if (Dispatcher.CheckAccess())
        {
            _ = action();
        }
        else
        {
            _ = Dispatcher.InvokeAsync(action);
        }
    }
}
