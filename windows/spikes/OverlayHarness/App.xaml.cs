using System.Windows;
using BG3HonorAssistant.Windows.Overlay;

namespace OverlayHarness;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs eventArgs)
    {
        OverlayWindowService.EnablePerMonitorV2DpiAwareness();
        base.OnStartup(eventArgs);
    }
}
