using System.Windows.Controls;

namespace BG3HonorAssistant.App.Screens.Party;

public partial class PartyView : UserControl
{
    public PartyView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Landing.Attach(host);
        Member.Attach(host);
        Roster.Attach(host);
        Abilities.Attach(host);
        ManualBuild.Attach(host);
        BuildImport.Attach(host);
    }
}
