using System.ComponentModel;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Navigation;
using BG3HonorAssistant.App.UI;
using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Overlay;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Windows.Credentials;
using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Shell;
using BG3HonorAssistant.Windows.Startup;
using Application = System.Windows.Application;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    private async void OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (loaded)
        {
            return;
        }

        loaded = true;
        SettingsScreen.OverlayDensityPicker.ItemsSource = Enum.GetValues<OverlayDensity>();
        SettingsScreen.RunDifficultyPicker.ItemsSource =
            RunDifficultyExtensions.SelectableOverlayDifficulties
                .Select(
                    difficulty => new DifficultyPickerRow(
                        difficulty,
                        difficulty == RunDifficulty.Honour
                            ? "Honour Mode"
                            : difficulty.ToString()))
                .ToList();
        SettingsScreen.RunRevealPicker.ItemsSource =
        new[]
        {
            new RevealPickerRow(RouteRevealPolicy.Everything, "Show everything"),
            new RevealPickerRow(RouteRevealPolicy.NextThree, "Only 3 tasks ahead"),
        };
        SettingsScreen.PackageStatusText.Text = PackageIdentity.TryGetFullName() is { } fullName
            ? $"Installed package: {fullName}"
            : "Unpackaged development launch. Packaged startup is unavailable.";
        SettingsScreen.StoragePathText.Text = $"Local state: {paths.Root}";
        RefreshCredentialStatus();
        await RefreshStartupAsync();
        RefreshView();
        if (controller.Preferences.OnboardingVersion < OnboardingFlow.Version)
        {
            StartOnboarding();
        }
    }

    private void OnClosing(object? sender, CancelEventArgs eventArgs)
    {
        _ = sender;
        if (Application.Current is App app && !app.ExitRequested)
        {
            eventArgs.Cancel = true;
            Hide();
            app.ShowTrayNotice();
        }
    }

    private void OnControllerStateChanged(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dispatcher.Invoke(
            () =>
            {
                InvalidatePartyUndoIfStateChanged();
                RefreshView();
            });
    }

    private void OnOverlayStateChanged(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dispatcher.Invoke(RefreshHeader);
    }

    protected override void OnClosed(EventArgs eventArgs)
    {
        controller.StateChanged -= OnControllerStateChanged;
        overlay.StateChanged -= OnOverlayStateChanged;
        overlay.OpenRouteRequested -= OnOverlayOpenRouteRequested;
        overlay.OpenChatRequested -= OnOverlayOpenChatRequested;
        overlay.TaskDoneRequested -= OnOverlayTaskDoneRequested;
        overlay.SnoozeRequested -= OnOverlaySnoozeRequested;
        overlay.MuteRequested -= OnOverlayMuteRequested;
        overlay.PinRequested -= OnOverlayPinRequested;
        CancelProviderOperations();
        chatLines.Clear();
        base.OnClosed(eventArgs);
    }
}
