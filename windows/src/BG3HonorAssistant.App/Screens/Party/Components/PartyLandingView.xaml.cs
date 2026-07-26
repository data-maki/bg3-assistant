using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class PartyLandingView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public PartyLandingView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnManagePartyClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnManagePartyClick(sender, eventArgs);

    private void OnPartyMemberSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnPartyMemberSelectionChanged(sender, eventArgs);
}
