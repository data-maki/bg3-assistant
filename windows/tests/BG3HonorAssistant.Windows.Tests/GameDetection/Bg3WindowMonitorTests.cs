using BG3HonorAssistant.Windows.GameDetection;

namespace BG3HonorAssistant.Windows.Tests.GameDetection;

public sealed class Bg3WindowMonitorTests
{
    [Fact]
    public void RefreshPublishesOnlyChangesIncludingGameExit()
    {
        var first = new Bg3WindowInfo(
            42,
            "bg3",
            new nint(123),
            new WindowBounds(-1920, 0, 0, 1080),
            144);
        var moved = first with
        {
            Bounds = new WindowBounds(100, 80, 2020, 1160),
            Dpi = 192,
        };
        var locator = new SequenceLocator(first, first, moved, null);
        using var monitor = new Bg3WindowMonitor(locator);
        var observed = new List<Bg3WindowInfo?>();
        monitor.WindowChanged += (_, args) => observed.Add(args.Window);

        monitor.Refresh();
        monitor.Refresh();
        monitor.Refresh();
        monitor.Refresh();

        Assert.Equal([first, moved, null], observed);
        Assert.Null(monitor.Current);
    }

    private sealed class SequenceLocator(params Bg3WindowInfo?[] windows) : IBg3WindowLocator
    {
        private readonly Queue<Bg3WindowInfo?> windows = new(windows);

        public Bg3WindowInfo? FindBestWindow()
        {
            return windows.Dequeue();
        }
    }
}
