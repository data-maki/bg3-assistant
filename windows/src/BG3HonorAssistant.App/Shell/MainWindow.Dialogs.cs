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
    private void ShowActionConfirmation(
        string title,
        string body,
        string confirmLabel,
        Func<Task> confirm,
        Action? cancel = null)
    {
        pendingConfirmationAction = confirm;
        pendingConfirmationCancel = cancel;
        Dialogs.ActionConfirmationTitleText.Text = title;
        Dialogs.ActionConfirmationBodyText.Text = body;
        Dialogs.ActionConfirmationConfirmButton.Content = confirmLabel;
        Dialogs.ActionConfirmationOverlay.Visibility = Visibility.Visible;
    }

    internal async void OnConfirmActionClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var action = pendingConfirmationAction;
        pendingConfirmationAction = null;
        pendingConfirmationCancel = null;
        Dialogs.ActionConfirmationOverlay.Visibility = Visibility.Collapsed;
        if (action is not null)
        {
            await action();
        }
    }

    internal void OnCancelActionClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var cancel = pendingConfirmationCancel;
        pendingConfirmationAction = null;
        pendingConfirmationCancel = null;
        Dialogs.ActionConfirmationOverlay.Visibility = Visibility.Collapsed;
        cancel?.Invoke();
    }

    private void ShowError(string message)
    {
        MessageBox.Show(
            this,
            message,
            "BG3 Honor Assistant",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }
}
