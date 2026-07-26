using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class PartyRosterView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public PartyRosterView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnPartyBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyBackClick(sender, eventArgs);

    private void OnRosterStatusChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnRosterStatusChanged(sender, eventArgs);
}
