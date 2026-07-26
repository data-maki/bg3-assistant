using System.Globalization;
using System.Windows;
using BG3HonorAssistant.Windows.Overlay;

namespace GameWindowHost;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs eventArgs)
    {
        OverlayWindowService.EnablePerMonitorV2DpiAwareness();
        base.OnStartup(eventArgs);

        var options = HostOptions.Parse(eventArgs.Args);
        var window = new MainWindow(options);
        MainWindow = window;
        window.Show();
    }

    internal sealed record HostOptions(
        bool Borderless,
        string Title,
        double Left,
        double Top,
        double Width,
        double Height)
    {
        internal static HostOptions Parse(IReadOnlyList<string> arguments)
        {
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (var index = 0; index < arguments.Count; index++)
            {
                var argument = arguments[index];
                if (!argument.StartsWith("--", StringComparison.Ordinal))
                {
                    continue;
                }

                var separator = argument.IndexOf('=');
                if (separator > 2)
                {
                    values[argument[2..separator]] = argument[(separator + 1)..];
                }
                else if (index + 1 < arguments.Count &&
                         !arguments[index + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    values[argument[2..]] = arguments[++index];
                }
                else
                {
                    values[argument[2..]] = "true";
                }
            }

            return new HostOptions(
                Borderless: values.ContainsKey("borderless"),
                Title: values.GetValueOrDefault("title", "BG3 controlled window host"),
                Left: GetDouble(values, "left", 120),
                Top: GetDouble(values, "top", 120),
                Width: GetDouble(values, "width", 1280),
                Height: GetDouble(values, "height", 720));
        }

        private static double GetDouble(
            IReadOnlyDictionary<string, string> values,
            string name,
            double fallback)
        {
            return values.TryGetValue(name, out var value) &&
                   double.TryParse(
                       value,
                       NumberStyles.Float,
                       CultureInfo.InvariantCulture,
                       out var parsed)
                ? parsed
                : fallback;
        }
    }
}
