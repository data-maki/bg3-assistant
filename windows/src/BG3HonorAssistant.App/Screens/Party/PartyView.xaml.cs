using System.Windows;
using System.Windows.Controls;

namespace BG3HonorAssistant.App.Screens.Party;

public partial class PartyView : System.Windows.Controls.UserControl
{
    private MainWindow Host { get; set; } = null!;

    public PartyView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
        Landing.Attach(host);
        Member.Attach(host);
        Roster.Attach(host);
        Abilities.Attach(host);
        ManualBuild.Attach(host);
        BuildImport.Attach(host);
    }

    private void OnUndoPartyChangeClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnUndoPartyChangeClick(sender, eventArgs);

    private void OnDismissPartyUndoClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnDismissPartyUndoClick(sender, eventArgs);
}
