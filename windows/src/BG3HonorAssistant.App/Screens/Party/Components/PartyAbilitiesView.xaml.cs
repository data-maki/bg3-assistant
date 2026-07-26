using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class PartyAbilitiesView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public PartyAbilitiesView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnAbilitySetupChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnAbilitySetupChanged(sender, eventArgs);

    private void OnAbilitySourceActionClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnAbilitySourceActionClick(sender, eventArgs);

    private void OnApplyAbilitySetupClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnApplyAbilitySetupClick(sender, eventArgs);

    private void OnPartyCharacterBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyCharacterBackClick(sender, eventArgs);
}
