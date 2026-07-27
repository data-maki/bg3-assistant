using System.ComponentModel;
using System.IO;
using System.Text.Json;
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
using BG3HonorAssistant.Core.Serialization;
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
    internal async void OnRunSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            SettingsScreen.RunPicker.SelectedItem is not SavedRunPickerRow selected ||
            selected.Run.Id == controller.Run.Id)
        {
            return;
        }

        if (!await controller.SwitchRunAsync(selected.Run.Id))
        {
            ShowError("That run could not be loaded. Its stored bytes were left unchanged.");
        }
    }

    internal void OnNewRunClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dialogs.NewRunConfirmationTitleText.Text =
            $"Create a new run? {controller.Run.Name ?? "Honor Run"} stays saved and can be resumed anytime.";
        Dialogs.NewRunConfirmationOverlay.Visibility = Visibility.Visible;
    }

    internal async void OnCreateRunWithPresetClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dialogs.NewRunConfirmationOverlay.Visibility = Visibility.Collapsed;
        await controller.CreateRunWithCurrentPartyPresetAsync(
            NewRunName(),
            controller.Run.Difficulty ?? RunDifficulty.Honour,
            controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything);
        SettingsScreen.NewRunNameTextBox.Clear();
    }

    internal async void OnCreateDefaultRunClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dialogs.NewRunConfirmationOverlay.Visibility = Visibility.Collapsed;
        await controller.CreateRunAsync(
            NewRunName(),
            controller.Run.Difficulty ?? RunDifficulty.Honour,
            controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything);
        SettingsScreen.NewRunNameTextBox.Clear();
    }

    internal void OnCancelNewRunClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dialogs.NewRunConfirmationOverlay.Visibility = Visibility.Collapsed;
    }

    private string NewRunName() =>
        string.IsNullOrWhiteSpace(SettingsScreen.NewRunNameTextBox.Text)
            ? $"Honor Run {DateTime.Now:yyyy-MM-dd HH:mm}"
            : SettingsScreen.NewRunNameTextBox.Text.Trim();

    internal async void OnRenameRunClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (!string.IsNullOrWhiteSpace(SettingsScreen.RunNameTextBox.Text))
        {
            await controller.RenameRunAsync(SettingsScreen.RunNameTextBox.Text);
        }
    }

    internal async void OnOverlayPreferenceChanged(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await PersistOverlayPreferencesAsync();
    }

    internal async void OnOverlayPreferenceChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await PersistOverlayPreferencesAsync();
    }

    private async Task PersistOverlayPreferencesAsync()
    {
        if (refreshing ||
            SettingsScreen.OverlayDensityPicker.SelectedItem is not OverlayDensity density)
        {
            return;
        }

        await controller.UpdatePreferencesAsync(
            controller.Preferences with
            {
                OverlayDensity = density,
                ShowOverlayWhileGameRuns = SettingsScreen.ShowOverlayCheckBox.IsChecked == true,
                ReducedMotion = controller.Preferences.ReducedMotion,
            });
    }

    internal async void OnRunSettingChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            SettingsScreen.RunDifficultyPicker.SelectedItem is not DifficultyPickerRow difficulty ||
            SettingsScreen.RunRevealPicker.SelectedItem is not RevealPickerRow reveal)
        {
            return;
        }

        await controller.UpdateRunSettingsAsync(difficulty.Value, reveal.Value);
    }

    internal void OnReplayTourClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        StartOnboarding();
    }

    internal async void OnStartupToggleClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var status = SettingsScreen.StartupToggle.IsChecked == true
            ? await startup.RequestEnableFromUserActionAsync()
            : await startup.DisableFromUserActionAsync();
        ApplyStartupStatus(status);
    }

    private async Task RefreshStartupAsync()
    {
        ApplyStartupStatus(await startup.GetStatusAsync());
    }

    private void ApplyStartupStatus(StartupRegistrationStatus status)
    {
        SettingsScreen.StartupStatusText.Text = status.Message;
        SettingsScreen.StartupToggle.IsChecked =
            status.State is StartupRegistrationState.Enabled or
                StartupRegistrationState.EnabledByPolicy;
        SettingsScreen.StartupToggle.IsEnabled =
            status.State is StartupRegistrationState.Enabled or
                StartupRegistrationState.Disabled;
    }

    internal void OnSaveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var key = SettingsScreen.OpenRouterKeyPasswordBox.Password.Trim();
        SettingsScreen.OpenRouterKeyPasswordBox.Clear();
        if (key.Length == 0)
        {
            SettingsScreen.OpenRouterKeyStatusText.Text =
                "Enter an OpenRouter API key before saving.";
            return;
        }

        CancelProviderOperations();
        try
        {
            credentialStore.Save(key);
            openRouterKeyConfigured = true;
            SettingsScreen.OpenRouterKeyStatusText.Text =
                "Key saved for this Windows user in Windows Credential Manager.";
        }
        catch (Exception exception)
        {
            openRouterKeyConfigured = false;
            SettingsScreen.OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not save the key: {exception.Message}";
        }

        UpdateOpenRouterPanels();
        UpdateNetworkButtons();
    }

    internal void OnShowOpenRouterEntryClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        SettingsScreen.OpenRouterSavedPanel.Visibility = Visibility.Collapsed;
        SettingsScreen.OpenRouterEntryPanel.Visibility = Visibility.Visible;
        SettingsScreen.OpenRouterKeyPasswordBox.Focus();
    }

    internal async void OnTestOpenRouterClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (keyTestCancellation is not null)
        {
            SettingsScreen.OpenRouterKeyStatusText.Text =
                "Cancelling OpenRouter connection test…";
            keyTestOperationVersion++;
            keyTestCancellation.Cancel();
            return;
        }

        string? apiKey;
        try
        {
            apiKey = credentialStore.Read();
        }
        catch (Exception exception)
        {
            SettingsScreen.OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not read the key: {exception.Message}";
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            SettingsScreen.OpenRouterKeyStatusText.Text = "No OpenRouter key is saved.";
            UpdateNetworkButtons();
            return;
        }

        var cancellation = new CancellationTokenSource();
        keyTestCancellation = cancellation;
        var operationVersion = ++keyTestOperationVersion;
        SettingsScreen.OpenRouterKeyStatusText.Text =
            $"Testing the pinned {OpenRouterClient.ModelDisplayName} model…";
        UpdateNetworkButtons();
        try
        {
            var result = await openRouter.CompleteAsync(
                apiKey,
                [
                    new OpenRouterMessage(
                        "system",
                        "Return strict JSON matching the supplied schema. Put the single word OK in answer."),
                    new OpenRouterMessage("user", "Connection test."),
                ],
                ChatPromptBuilder.ResponseSchema,
                "connection_test",
                512,
                cancellation.Token);
            _ = ChatPromptBuilder.DecodeAnswer(result);
            if (operationVersion == keyTestOperationVersion)
            {
                openRouterKeyConfigured = true;
                SettingsScreen.OpenRouterKeyStatusText.Text =
                    $"Connected successfully to {OpenRouterClient.Model}.";
            }
        }
        catch (OperationCanceledException)
        {
            if (operationVersion == keyTestOperationVersion)
            {
                SettingsScreen.OpenRouterKeyStatusText.Text =
                    "OpenRouter connection test cancelled.";
            }
        }
        catch (Exception exception)
        {
            if (operationVersion == keyTestOperationVersion)
            {
                SettingsScreen.OpenRouterKeyStatusText.Text =
                    $"OpenRouter connection test failed: {exception.Message}";
            }
        }
        finally
        {
            cancellation.Dispose();
            if (ReferenceEquals(keyTestCancellation, cancellation))
            {
                keyTestCancellation = null;
            }

            UpdateNetworkButtons();
        }
    }

    internal void OnRemoveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        CancelProviderOperations();
        try
        {
            var removed = credentialStore.Delete();
            openRouterKeyConfigured = false;
            SettingsScreen.OpenRouterKeyPasswordBox.Clear();
            SettingsScreen.OpenRouterKeyStatusText.Text = removed
                ? "OpenRouter key removed from Windows Credential Manager."
                : "No saved OpenRouter key was present.";
        }
        catch (Exception exception)
        {
            SettingsScreen.OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not remove the key: {exception.Message}";
        }

        UpdateOpenRouterPanels();
        UpdateNetworkButtons();
    }

    private void RefreshCredentialStatus()
    {
        try
        {
            openRouterKeyConfigured =
                !string.IsNullOrWhiteSpace(credentialStore.Read());
            SettingsScreen.OpenRouterKeyStatusText.Text = openRouterKeyConfigured
                ? "A key is saved for this Windows user in Windows Credential Manager."
                : "No OpenRouter key is saved.";
        }
        catch (Exception exception)
        {
            openRouterKeyConfigured = false;
            SettingsScreen.OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager is unavailable: {exception.Message}";
        }

        UpdateOpenRouterPanels();
        UpdateNetworkButtons();
    }

    private void UpdateOpenRouterPanels()
    {
        SettingsScreen.OpenRouterSavedPanel.Visibility = openRouterKeyConfigured
            ? Visibility.Visible
            : Visibility.Collapsed;
        SettingsScreen.OpenRouterEntryPanel.Visibility = openRouterKeyConfigured
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void CancelProviderOperations()
    {
        chatOperationVersion++;
        importOperationVersion++;
        keyTestOperationVersion++;
        chatCancellation?.Cancel();
        importCancellation?.Cancel();
        keyTestCancellation?.Cancel();
    }

    internal void OnReportBugClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        try
        {
            launcher.OpenSupportEmail();
        }
        catch (Exception exception)
        {
            ShowError(
                $"Could not open an email app. Report bugs to jcllobet@gmail.com. {exception.Message}");
        }
    }

    internal void OnOpenLegalLinkClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string url })
        {
            try
            {
                launcher.OpenExternalMap(url);
            }
            catch (Exception exception)
            {
                ShowError($"The legal link could not be opened: {exception.Message}");
            }
        }
    }

    internal void OnOpenThirdPartyNoticesClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        try
        {
            launcher.OpenLocalFile(
                Path.Combine(
                    AppContext.BaseDirectory,
                    "Resources",
                    "THIRD_PARTY_NOTICES.md"));
        }
        catch (Exception exception)
        {
            ShowError($"The bundled third-party notices could not be opened: {exception.Message}");
        }
    }

    private void UpdateNetworkButtons()
    {
        if (!loaded)
        {
            return;
        }

        ChatScreen.SendChatButton.IsEnabled =
            openRouterKeyConfigured &&
            controller.Payload.RouteAvailable;
        ChatScreen.SendChatButton.Content =
            chatCancellation is null ? "↑" : "×";
        ChatScreen.SendChatButton.ToolTip =
            chatCancellation is null
                ? "Send typed question"
                : "Cancel chat request";
        PartyScreen.BuildImport.PartyImportBuildButton.IsEnabled =
            openRouterKeyConfigured;
        PartyScreen.BuildImport.PartyImportBuildButton.Content =
            importCancellation is null ? "⇩  Import" : "×  Cancel";
        SettingsScreen.TestOpenRouterButton.IsEnabled =
            openRouterKeyConfigured;
        SettingsScreen.TestOpenRouterButton.Content =
            keyTestCancellation is null ? "Test" : "Cancel";
    }
    private void RefreshSettingsScreen()
    {
        var runRows = controller.Runs.Select(
                run =>
                {
                    var level = TryReadRunLevel(run);
                    return new SavedRunPickerRow(
                        run,
                        level is null ? run.Name : $"{run.Name} · L{level}");
                })
            .ToList();
        SettingsScreen.RunPicker.ItemsSource = runRows;
        SettingsScreen.RunPicker.SelectedItem =
            runRows.FirstOrDefault(row => row.Run.IsActive);
        if (!SettingsScreen.RunNameTextBox.IsKeyboardFocusWithin)
        {
            SettingsScreen.RunNameTextBox.Text = controller.Run.Name ?? "Honor Run";
        }
        SettingsScreen.RunDifficultyPicker.SelectedItem =
            SettingsScreen.RunDifficultyPicker.Items
                .OfType<DifficultyPickerRow>()
                .FirstOrDefault(
                    row => row.Value ==
                           (controller.Run.Difficulty ?? RunDifficulty.Honour));
        SettingsScreen.RunRevealPicker.SelectedItem =
            SettingsScreen.RunRevealPicker.Items
                .OfType<RevealPickerRow>()
                .FirstOrDefault(
                    row => row.Value ==
                           (controller.Run.RouteRevealPolicy ??
                            RouteRevealPolicy.Everything));
        SettingsScreen.OpenRouterModelText.Text = OpenRouterClient.Model;

        SettingsScreen.ShowOverlayCheckBox.IsChecked =
            controller.Preferences.ShowOverlayWhileGameRuns;
        SettingsScreen.OverlayDensityPicker.SelectedItem = controller.Preferences.OverlayDensity;

        SettingsScreen.TestOpenRouterButton.IsEnabled =
            openRouterKeyConfigured;

        SettingsScreen.DiagnosticsText.Text =
            $"Guide version: {controller.Guide.GuideVersion}\n" +
            $"Run id: {controller.Run.Id}\n" +
            $"Database: {paths.Database}\n" +
            $"Package: {(PackageIdentity.IsPackaged ? "MSIX" : "unpackaged development")}\n" +
            $"Supported windows: bg3.exe, bg3_dx11.exe\n" +
            $"Detected window: {overlay.GameStatus}\n" +
            $"Recovery: {controller.RecoveryNotice ?? "not needed"}\n" +
            $"OpenRouter: {(openRouterKeyConfigured ? "key configured" : "not configured")} · {OpenRouterClient.Model}\n" +
            "Game memory, files, saves, injection, hooks, services, and elevation: unused";
    }

    private static int? TryReadRunLevel(SavedRun saved)
    {
        try
        {
            var run = JsonSerializer.Deserialize<HonorRun>(
                saved.SnapshotJson,
                JsonDefaults.Create());
            run?.NormalizeRoster();
            return run?.Party.Count == 0
                ? null
                : run?.Party.Min(member => member.Level);
        }
        catch (JsonException)
        {
            return null;
        }
    }

}
