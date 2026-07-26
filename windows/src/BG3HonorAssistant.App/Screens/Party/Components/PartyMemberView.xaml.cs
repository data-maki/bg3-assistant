using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class PartyMemberView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public PartyMemberView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnCompareBuildsClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCompareBuildsClick(sender, eventArgs);

    private void OnManualBuildClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnManualBuildClick(sender, eventArgs);

    private void OnOpenBuildImportClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOpenBuildImportClick(sender, eventArgs);

    private void OnPartyAbilitiesClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyAbilitiesClick(sender, eventArgs);

    private void OnPartyBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyBackClick(sender, eventArgs);

    private void OnPartyBuildChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnPartyBuildChanged(sender, eventArgs);

    private void OnPartyBuildComparisonChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnPartyBuildComparisonChanged(sender, eventArgs);

    private void OnPartyLevelChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnPartyLevelChanged(sender, eventArgs);

    private void OnResetCharacterClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnResetCharacterClick(sender, eventArgs);
}
