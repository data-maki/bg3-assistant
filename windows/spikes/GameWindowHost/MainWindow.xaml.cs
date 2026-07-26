using System.Windows;

namespace GameWindowHost;

public partial class MainWindow : Window
{
    internal MainWindow(App.HostOptions options)
    {
        InitializeComponent();

        Title = options.Title;
        Left = options.Left;
        Top = options.Top;
        Width = options.Width;
        Height = options.Height;
        WindowStyle = options.Borderless
            ? WindowStyle.None
            : WindowStyle.SingleBorderWindow;
        ModeText.Text = options.Borderless
            ? "Borderless-style geometry"
            : "Windowed-style geometry";
    }
}
