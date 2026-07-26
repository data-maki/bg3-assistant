using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Settings;

public partial class SettingsView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public SettingsView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnNewRunClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnNewRunClick(sender, eventArgs);

    private void OnOpenLegalLinkClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOpenLegalLinkClick(sender, eventArgs);

    private void OnOpenThirdPartyNoticesClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOpenThirdPartyNoticesClick(sender, eventArgs);

    private void OnOverlayPreferenceChanged(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOverlayPreferenceChanged(sender, eventArgs);

    private void OnOverlayPreferenceChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnOverlayPreferenceChanged(sender, eventArgs);

    private void OnRemoveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRemoveOpenRouterKeyClick(sender, eventArgs);

    private void OnRenameRunClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRenameRunClick(sender, eventArgs);

    private void OnReplayTourClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnReplayTourClick(sender, eventArgs);

    private void OnReportBugClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnReportBugClick(sender, eventArgs);

    private void OnRunSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnRunSelectionChanged(sender, eventArgs);

    private void OnRunSettingChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnRunSettingChanged(sender, eventArgs);

    private void OnSaveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSaveOpenRouterKeyClick(sender, eventArgs);

    private void OnShowOpenRouterEntryClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnShowOpenRouterEntryClick(sender, eventArgs);

    private void OnStartupToggleClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnStartupToggleClick(sender, eventArgs);

    private void OnTestOpenRouterClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnTestOpenRouterClick(sender, eventArgs);
}
