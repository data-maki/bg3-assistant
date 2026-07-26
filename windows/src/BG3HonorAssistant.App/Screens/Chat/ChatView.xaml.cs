using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Screens.Chat;

public partial class ChatView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public ChatView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnChatDraftKeyDown(object sender, KeyEventArgs eventArgs) =>
        Host.OnChatDraftKeyDown(sender, eventArgs);

    private void OnChatScopeClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnChatScopeClick(sender, eventArgs);

    private void OnQuickChatClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnQuickChatClick(sender, eventArgs);

    private void OnSendChatClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSendChatClick(sender, eventArgs);
}
