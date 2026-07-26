using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class ManualBuildView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public ManualBuildView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnManualAbilityAdjustClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnManualAbilityAdjustClick(sender, eventArgs);

    private void OnManualBuildNameLostFocus(object sender, RoutedEventArgs eventArgs) =>
        Host.OnManualBuildNameLostFocus(sender, eventArgs);

    private void OnManualChoiceClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnManualChoiceClick(sender, eventArgs);

    private void OnManualClassChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnManualClassChanged(sender, eventArgs);

    private void OnManualLevelSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnManualLevelSelectionChanged(sender, eventArgs);

    private void OnPartyCharacterBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyCharacterBackClick(sender, eventArgs);
}
