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
    private bool runtimeDisposed;

    public bool ExitRequested { get; private set; }

    protected override async void OnStartup(StartupEventArgs eventArgs)
    {
        OverlayWindowService.EnablePerMonitorV2DpiAwareness();
        base.OnStartup(eventArgs);

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
            if (AppLaunchPolicy.ShouldShowPlanner(controller.Preferences))
            {
                window.Show();
            }
            else
            {
                InitializeHiddenPlanner(window);
            }
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
        _ = ExitApplicationAsync();
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs eventArgs)
    {
        ExitRequested = true;
        try
        {
            _ = controller?.SealAndFlushAsync().Wait(TimeSpan.FromSeconds(5));
        }
        catch (AggregateException)
        {
            // SQLite transactions remain atomic if Windows ends the session
            // after the bounded flush attempt.
        }

        DisposeRuntime();
        base.OnSessionEnding(eventArgs);
    }

    private async Task ExitApplicationAsync()
    {
        try
        {
            if (controller is not null)
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                await controller.SealAndFlushAsync(timeout.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // Do not trap the user in the process indefinitely. Every
            // individual SQLite write remains transactional.
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                $"The latest durable state could not be fully saved before exit.\n\n" +
                $"{exception.GetBaseException().Message}",
                "BG3 Honor Assistant",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        finally
        {
            DisposeRuntime();
            Shutdown();
        }
    }

    private void DisposeRuntime()
    {
        if (runtimeDisposed)
        {
            return;
        }

        runtimeDisposed = true;
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
    }

    protected override void OnExit(ExitEventArgs eventArgs)
    {
        DisposeRuntime();
        base.OnExit(eventArgs);
    }

    private static void InitializeHiddenPlanner(Window window)
    {
        var showActivated = window.ShowActivated;
        var showInTaskbar = window.ShowInTaskbar;
        var opacity = window.Opacity;
        window.ShowActivated = false;
        window.ShowInTaskbar = false;
        window.Opacity = 0D;
        window.Show();
        window.Hide();
        window.Opacity = opacity;
        window.ShowInTaskbar = showInTaskbar;
        window.ShowActivated = showActivated;
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
