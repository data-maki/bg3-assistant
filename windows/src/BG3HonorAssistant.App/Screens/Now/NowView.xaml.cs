using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Now;

public partial class NowView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public NowView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnClearTargetClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnClearTargetClick(sender, eventArgs);

    private void OnCompleteCurrentClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCompleteCurrentClick(sender, eventArgs);

    private void OnFollowRouteClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnFollowRouteClick(sender, eventArgs);

    private void OnMuteClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnMuteClick(sender, eventArgs);

    private void OnNowMoreChanged(object sender, RoutedEventArgs eventArgs) =>
        Host.OnNowMoreChanged(sender, eventArgs);

    private void OnPinFightClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPinFightClick(sender, eventArgs);

    private void OnRevisitCurrentClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRevisitCurrentClick(sender, eventArgs);

    private void OnSkipCurrentClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSkipCurrentClick(sender, eventArgs);

    private void OnSnoozeClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSnoozeClick(sender, eventArgs);
}
