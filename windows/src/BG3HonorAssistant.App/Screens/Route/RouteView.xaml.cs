using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Route;

public partial class RouteView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public RouteView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnArchivedRouteSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnArchivedRouteSelectionChanged(sender, eventArgs);

    private void OnCompleteSelectedStepClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCompleteSelectedStepClick(sender, eventArgs);

    private void OnFocusSelectedStepClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnFocusSelectedStepClick(sender, eventArgs);

    private void OnMarkRouteGearObtainedClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnMarkRouteGearObtainedClick(sender, eventArgs);

    private void OnOpenRouteGearLinkClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOpenRouteGearLinkClick(sender, eventArgs);

    private void OnOpenRouteSourceClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOpenRouteSourceClick(sender, eventArgs);

    private void OnRecordOutcomeClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRecordOutcomeClick(sender, eventArgs);

    private void OnRevisitSelectedStepClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRevisitSelectedStepClick(sender, eventArgs);

    private void OnRouteBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRouteBackClick(sender, eventArgs);

    private void OnRouteFilterButtonClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRouteFilterButtonClick(sender, eventArgs);

    private void OnRouteSelectionChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnRouteSelectionChanged(sender, eventArgs);

    private void OnSkipSelectedStepClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSkipSelectedStepClick(sender, eventArgs);

    private void OnTrackRouteGearClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnTrackRouteGearClick(sender, eventArgs);
}
