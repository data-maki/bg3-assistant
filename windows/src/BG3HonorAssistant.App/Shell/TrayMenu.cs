using BG3HonorAssistant.Infrastructure.Persistence;

namespace BG3HonorAssistant.App;

public sealed record TrayMenuActions(
    Action ShowOverlay,
    Action OpenPlanner,
    Action OpenMap,
    Action<string> SwitchRun,
    Action LaunchGame,
    Action TogglePet,
    Action OpenSettings,
    Action Quit);

public sealed class TrayMenu : IDisposable
{
    private readonly TrayMenuActions actions;
    private readonly System.Windows.Forms.ToolStripMenuItem runMenu;
    private readonly System.Windows.Forms.ToolStripMenuItem petMenuItem;

    public TrayMenu(TrayMenuActions actions)
    {
        this.actions = actions;
        Menu = new System.Windows.Forms.ContextMenuStrip();
        Menu.Items.Add("Show Overlay", null, (_, _) => actions.ShowOverlay());
        Menu.Items.Add("Open Planner", null, (_, _) => actions.OpenPlanner());
        Menu.Items.Add("Open Map", null, (_, _) => actions.OpenMap());
        runMenu = new System.Windows.Forms.ToolStripMenuItem("Run");
        Menu.Items.Add(runMenu);
        Menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        Menu.Items.Add(
            "Launch Baldur's Gate 3",
            null,
            (_, _) => actions.LaunchGame());
        Menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        petMenuItem = new System.Windows.Forms.ToolStripMenuItem(
            "Hide Pet",
            null,
            (_, _) => actions.TogglePet());
        Menu.Items.Add(petMenuItem);
        Menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        Menu.Items.Add("Settings", null, (_, _) => actions.OpenSettings());
        Menu.Items.Add("Quit", null, (_, _) => actions.Quit());
    }

    public System.Windows.Forms.ContextMenuStrip Menu { get; }

    public void Refresh(
        string currentRunName,
        IReadOnlyList<SavedRun> runs,
        bool petVisible)
    {
        runMenu.Text = $"Run: {currentRunName}";
        runMenu.DropDownItems.Clear();
        foreach (var run in runs)
        {
            var runId = run.Id;
            runMenu.DropDownItems.Add(
                new System.Windows.Forms.ToolStripMenuItem(
                    run.Name,
                    null,
                    (_, _) => actions.SwitchRun(runId))
                {
                    Checked = run.IsActive,
                    CheckOnClick = false,
                });
        }

        if (runMenu.DropDownItems.Count == 0)
        {
            runMenu.DropDownItems.Add(
                new System.Windows.Forms.ToolStripMenuItem("No saved runs")
                {
                    Enabled = false,
                });
        }

        petMenuItem.Text = petVisible ? "Hide Pet" : "Show Pet";
    }

    public void Dispose()
    {
        Menu.Dispose();
    }
}
