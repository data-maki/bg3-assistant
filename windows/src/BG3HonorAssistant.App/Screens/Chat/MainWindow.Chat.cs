using System.ComponentModel;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Navigation;
using BG3HonorAssistant.App.UI;
using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Overlay;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Windows.Credentials;
using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Shell;
using BG3HonorAssistant.Windows.Startup;
using Application = System.Windows.Application;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    internal async void OnSendChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await SendChatAsync();
    }

    internal async void OnQuickChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string prompt })
        {
            await SendChatAsync(prompt);
        }
    }

    internal void OnChatScopeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            Enum.TryParse<ChatScope>(raw, out var scope))
        {
            chatScope = scope;
            UpdateChatScopeButtons();
        }
    }

    private void UpdateChatScopeButtons()
    {
        var selected = chatScope;
        foreach (var (button, scope) in new[]
                 {
                     (ChatScreen.ChatCurrentScopeButton, ChatScope.Current),
                     (ChatScreen.ChatRouteScopeButton, ChatScope.Route),
                     (ChatScreen.ChatPartyScopeButton, ChatScope.Party),
                 })
        {
            var active = selected == scope;
            button.Background = active
                ? FindResource("BG3ProminentActionBrush") as Brush
                : FindResource("BG3ActionBrush") as Brush;
            button.Foreground = active
                ? FindResource("BG3ParchmentBrush") as Brush
                : FindResource("BG3MutedParchmentBrush") as Brush;
            button.FontWeight = active ? FontWeights.Bold : FontWeights.SemiBold;
        }
    }

    internal async void OnChatDraftKeyDown(object sender, KeyEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.Key == Key.Enter)
        {
            eventArgs.Handled = true;
            await SendChatAsync();
        }
    }

    private void OnClearChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        chatCancellation?.Cancel();
        chatLines.Clear();
        ChatScreen.ChatStatusText.Text = "Session chat cleared.";
        ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
        RenderChatHistory();
    }

    private async Task SendChatAsync(string? quickPrompt = null)
    {
        if (chatCancellation is not null)
        {
            return;
        }

        if (!controller.Payload.RouteAvailable)
        {
            ChatScreen.ChatStatusText.Text =
                $"{CurrentGoalRules.ActTwoUnavailableMessage}. Typed route chat is unavailable.";
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
            return;
        }

        var question = (quickPrompt ?? ChatScreen.ChatDraftTextBox.Text).Trim();
        if (question.Length == 0)
        {
            return;
        }

        string? apiKey;
        try
        {
            apiKey = credentialStore.Read();
        }
        catch (Exception exception)
        {
            ChatScreen.ChatStatusText.Text =
                $"Windows Credential Manager could not read the OpenRouter key: {exception.Message}";
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            SettingsScreen.OpenRouterKeyStatusText.Text =
                "No key is saved. Add one in Settings to use typed chat.";
            ChatScreen.ChatStatusText.Text =
                "Configure an OpenRouter key in Settings before sending typed chat.";
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
            PlannerTabs.SelectedIndex = 6;
            UpdateNetworkButtons();
            return;
        }

        var requestedRunId = controller.Run.Id;
        var requestedAct = controller.Run.SelectedAct ?? 1;
        var history = chatLines
            .Where(line => !line.IsError)
            .Select(line => new ChatMessage(line.Role, line.Text))
            .ToList();
        ChatPrompt prompt;
        try
        {
            prompt = ChatPromptBuilder.Build(
                controller.Run,
                controller.Payload,
                controller.CurrentStep,
                controller.ActiveParty,
                question,
                chatScope,
                history);
        }
        catch (InvalidOperationException exception)
        {
            ChatScreen.ChatStatusText.Text = exception.Message;
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
            return;
        }

        chatLines.Add(new ChatLineRow("user", question, [], IsError: false));
        ChatScreen.ChatDraftTextBox.Clear();
        RenderChatHistory();
        chatCancellation = new CancellationTokenSource();
        ChatScreen.ChatStatusText.Text =
            $"Waiting for {OpenRouterClient.ModelDisplayName}…";
        ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
        UpdateNetworkButtons();
        try
        {
            var structured = await openRouter.CompleteAsync(
                apiKey,
                prompt.Messages
                    .Select(message => new OpenRouterMessage(message.Role, message.Content))
                    .ToList(),
                ChatPromptBuilder.ResponseSchema,
                "bg3_guide_answer",
                1_200,
                chatCancellation.Token);
            var answer = ChatPromptBuilder.DecodeAnswer(structured);
            if (controller.Run.Id == requestedRunId &&
                (controller.Run.SelectedAct ?? 1) == requestedAct)
            {
                chatLines.Add(
                    new ChatLineRow(
                        "assistant",
                        answer,
                        prompt.Sources,
                        IsError: false));
                ChatScreen.ChatStatusText.Text =
                    $"Answered by the pinned {OpenRouterClient.ModelDisplayName} model.";
                ChatScreen.ChatStatusText.Visibility = Visibility.Collapsed;
                RenderChatHistory();
            }
        }
        catch (OperationCanceledException)
        {
            ChatScreen.ChatStatusText.Text = "Chat request cancelled.";
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
        }
        catch (OpenRouterException exception)
        {
            AddChatError(exception.Message);
        }
        catch (InvalidOperationException exception)
        {
            AddChatError(exception.Message);
        }
        finally
        {
            chatCancellation.Dispose();
            chatCancellation = null;
            UpdateNetworkButtons();
        }
    }

    private void AddChatError(string message)
    {
        chatLines.Add(new ChatLineRow("assistant", message, [], IsError: true));
        ChatScreen.ChatStatusText.Text =
            "OpenRouter could not answer. The local Now and Route tabs remain available.";
        ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
        RenderChatHistory();
    }

    private void EnsureChatContext()
    {
        var act = controller.Run.SelectedAct ?? 1;
        if (chatRunId == controller.Run.Id && chatAct == act)
        {
            return;
        }

        chatCancellation?.Cancel();
        chatLines.Clear();
        chatRunId = controller.Run.Id;
        chatAct = act;
        if (loaded)
        {
            ChatScreen.ChatStatusText.Text =
                "Chat context changed. The prior session history was cleared.";
            ChatScreen.ChatStatusText.Visibility = Visibility.Visible;
        }
    }

    private void RenderChatHistory()
    {
        if (!loaded)
        {
            return;
        }

        var document = new FlowDocument
        {
            PagePadding = new Thickness(8),
        };
        ChatScreen.ChatEmptyState.Visibility = chatLines.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;

        foreach (var line in chatLines)
        {
            var isUser = line.Role == "user";
            var paragraph = new Paragraph
            {
                Margin = isUser
                    ? new Thickness(70, 3, 0, 7)
                    : new Thickness(0, 3, 45, 4),
                Padding = new Thickness(9, 6, 9, 6),
                Background = isUser
                    ? (Brush)FindResource("BG3ProminentActionBrush")
                    : (Brush)FindResource("BG3InsetBrush"),
                Foreground = (Brush)FindResource("BG3ParchmentBrush"),
            };
            AppendMarkdown(paragraph, line.Text);
            if (line.Sources.Count > 0)
            {
                paragraph.Inlines.Add(new LineBreak());
                paragraph.Inlines.Add(new Run("Sources: "));
                for (var index = 0; index < line.Sources.Count; index++)
                {
                    if (index > 0)
                    {
                        paragraph.Inlines.Add(new Run(" · "));
                    }

                    AddLink(
                        paragraph,
                        line.Sources[index].Title,
                        line.Sources[index].Url);
                }
            }

            if (line.IsError)
            {
                paragraph.Foreground =
                    (Brush)FindResource("BG3DangerBrush");
            }

            document.Blocks.Add(paragraph);
        }

        ChatScreen.ChatHistoryBox.Document = document;
        ChatScreen.ChatHistoryBox.ScrollToEnd();
    }

    private void AppendMarkdown(Paragraph paragraph, string text)
    {
        var offset = 0;
        foreach (Match match in MarkdownLinkPattern.Matches(text))
        {
            if (match.Index > offset)
            {
                paragraph.Inlines.Add(new Run(text[offset..match.Index]));
            }

            AddLink(
                paragraph,
                match.Groups["label"].Value,
                match.Groups["url"].Value);
            offset = match.Index + match.Length;
        }

        if (offset < text.Length)
        {
            paragraph.Inlines.Add(new Run(text[offset..]));
        }
    }

    private void AddLink(Paragraph paragraph, string label, string rawUrl)
    {
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var url) ||
            url.Scheme is not ("http" or "https"))
        {
            paragraph.Inlines.Add(new Run(label));
            return;
        }

        var hyperlink = new Hyperlink(new Run(label))
        {
            NavigateUri = url,
        };
        hyperlink.RequestNavigate += OnChatLinkNavigate;
        paragraph.Inlines.Add(hyperlink);
    }

    private void OnChatLinkNavigate(
        object sender,
        RequestNavigateEventArgs eventArgs)
    {
        _ = sender;
        eventArgs.Handled = true;
        try
        {
            launcher.OpenExternalMap(eventArgs.Uri.AbsoluteUri);
        }
        catch (Exception)
        {
            ChatScreen.ChatStatusText.Text = "The selected source link could not be opened.";
        }
    }
    private void RefreshChatScreen()
    {
        EnsureChatContext();

        ChatScreen.ChatActContextText.Text =
            $"▧  Act {controller.Run.SelectedAct ?? 1} · {controller.Run.MapRegion}";
        ChatScreen.ChatPartyContextText.Text =
            $"♙  Active L{controller.LowestPartyLevel} · {controller.ActiveParty.Count}/4";
        ChatScreen.ChatRecommendedContextText.Text =
            $"✦  Recommended: {controller.CurrentStep?.Title ?? controller.GoalPresentation.Title}";
        UpdateChatScopeButtons();
        RenderChatHistory();
        ChatScreen.SendChatButton.IsEnabled =
            controller.Payload.RouteAvailable &&
            openRouterKeyConfigured &&
            chatCancellation is null;
    }

}
