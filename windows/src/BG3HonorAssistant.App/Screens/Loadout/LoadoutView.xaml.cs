using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Loadout;

public partial class LoadoutView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public LoadoutView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnEditLoadoutMemberClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnEditLoadoutMemberClick(sender, eventArgs);

    private void OnGearEquippedClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnGearEquippedClick(sender, eventArgs);

    private void OnGearMapClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnGearMapClick(sender, eventArgs);

    private void OnGearTargetClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnGearTargetClick(sender, eventArgs);

    private void OnGiveLoadoutGearClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnGiveLoadoutGearClick(sender, eventArgs);

    private void OnLoadoutBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnLoadoutBackClick(sender, eventArgs);

    private void OnLoadoutGearClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnLoadoutGearClick(sender, eventArgs);

    private void OnLoadoutMemberClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnLoadoutMemberClick(sender, eventArgs);

    private void OnRevertLoadoutPickClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnRevertLoadoutPickClick(sender, eventArgs);

    private void OnUseLoadoutPickClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnUseLoadoutPickClick(sender, eventArgs);
}
