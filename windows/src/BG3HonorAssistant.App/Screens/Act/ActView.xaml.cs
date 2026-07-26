using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Act;

public partial class ActView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public ActView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnActAcceptanceChanged(object sender, RoutedEventArgs eventArgs) =>
        Host.OnActAcceptanceChanged(sender, eventArgs);

    private void OnActGearMissedClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnActGearMissedClick(sender, eventArgs);

    private void OnActGearObtainedClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnActGearObtainedClick(sender, eventArgs);

    private void OnActLedgerClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnActLedgerClick(sender, eventArgs);

    private void OnAdvanceActClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnAdvanceActClick(sender, eventArgs);

    private void OnReturnActiveActClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnReturnActiveActClick(sender, eventArgs);
}
