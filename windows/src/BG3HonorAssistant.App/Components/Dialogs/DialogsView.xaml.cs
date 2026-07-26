using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Components.Dialogs;

public partial class DialogsView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public DialogsView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnCancelActionClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCancelActionClick(sender, eventArgs);

    private void OnCancelNewRunClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCancelNewRunClick(sender, eventArgs);

    private void OnCancelResetCharacterClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCancelResetCharacterClick(sender, eventArgs);

    private void OnConfirmActionClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnConfirmActionClick(sender, eventArgs);

    private void OnConfirmResetCharacterClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnConfirmResetCharacterClick(sender, eventArgs);

    private void OnCreateDefaultRunClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCreateDefaultRunClick(sender, eventArgs);

    private void OnCreateRunWithPresetClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCreateRunWithPresetClick(sender, eventArgs);
}
