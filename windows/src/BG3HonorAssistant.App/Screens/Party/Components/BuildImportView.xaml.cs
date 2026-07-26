using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Party.Components;

public partial class BuildImportView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public BuildImportView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnClosePartyBuildImportClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnClosePartyBuildImportClick(sender, eventArgs);

    private void OnPartyImportBuildClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnPartyImportBuildClick(sender, eventArgs);
}
