using BG3HonorAssistant.Infrastructure.Persistence;

namespace BG3HonorAssistant.App.Tests;

public sealed class TrayMenuTests
{
    [Fact]
    public void EveryCommandInvokesItsOwnedActionAndRunMenuTracksState()
    {
        var calls = new List<string>();
        using var tray = new TrayMenu(
            new TrayMenuActions(
                () => calls.Add("overlay"),
                () => calls.Add("planner"),
                () => calls.Add("map"),
                id => calls.Add($"run:{id}"),
                () => calls.Add("launch"),
                () => calls.Add("pet"),
                () => calls.Add("settings"),
                () => calls.Add("quit")));

        tray.Refresh(
            "Second",
            [
                new SavedRun(
                    "run-1",
                    "First",
                    "guide",
                    "{}",
                    DateTimeOffset.UnixEpoch,
                    DateTimeOffset.UnixEpoch,
                    false),
                new SavedRun(
                    "run-2",
                    "Second",
                    "guide",
                    "{}",
                    DateTimeOffset.UnixEpoch,
                    DateTimeOffset.UnixEpoch,
                    true),
            ],
            petVisible: true);

        Assert.Equal("Run: Second", tray.Menu.Items[3].Text);
        var runMenu = Assert.IsType<System.Windows.Forms.ToolStripMenuItem>(
            tray.Menu.Items[3]);
        Assert.False(
            Assert.IsType<System.Windows.Forms.ToolStripMenuItem>(
                runMenu.DropDownItems[0]).Checked);
        Assert.True(
            Assert.IsType<System.Windows.Forms.ToolStripMenuItem>(
                runMenu.DropDownItems[1]).Checked);
        Assert.Equal("Hide Pet", tray.Menu.Items[7].Text);

        tray.Menu.Items[0].PerformClick();
        tray.Menu.Items[1].PerformClick();
        tray.Menu.Items[2].PerformClick();
        runMenu.DropDownItems[0].PerformClick();
        tray.Menu.Items[5].PerformClick();
        tray.Menu.Items[7].PerformClick();
        tray.Menu.Items[9].PerformClick();
        tray.Menu.Items[10].PerformClick();

        Assert.Equal(
            [
                "overlay",
                "planner",
                "map",
                "run:run-1",
                "launch",
                "pet",
                "settings",
                "quit",
            ],
            calls);

        tray.Refresh("Second", [], petVisible: false);
        Assert.Equal("Show Pet", tray.Menu.Items[7].Text);
        Assert.False(runMenu.DropDownItems[0].Enabled);
    }
}
