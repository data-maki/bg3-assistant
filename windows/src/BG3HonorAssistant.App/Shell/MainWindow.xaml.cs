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
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow : Window
{
    private static readonly Regex MarkdownLinkPattern = new(
        @"\[(?<label>[^\]\r\n]{1,200})\]\((?<url>https?://[^\s)]+)\)",
        RegexOptions.Compiled |
        RegexOptions.CultureInvariant |
        RegexOptions.NonBacktracking);
    private readonly AssistantController controller;
    private readonly StartupTaskService startup;
    private readonly GameLauncher launcher;
    private readonly AppDataPaths paths;
    private readonly OverlayCoordinator overlay;
    private readonly CredentialStore credentialStore;
    private readonly IOpenRouterClient openRouter;
    private readonly BuildImportCoordinator buildImporter;
    private readonly List<ChatLineRow> chatLines = [];
    private CancellationTokenSource? chatCancellation;
    private CancellationTokenSource? importCancellation;
    private CancellationTokenSource? keyTestCancellation;
    private Func<Task>? pendingConfirmationAction;
    private Action? pendingConfirmationCancel;
    private string? chatRunId;
    private int chatAct;
    private bool openRouterKeyConfigured;
    private bool refreshing;
    private bool loaded;
    private int onboardingIndex;
    private OnboardingMode onboardingMode = OnboardingMode.Fresh;
    private RunDifficulty onboardingDifficulty = RunDifficulty.Honour;
    private RouteRevealPolicy onboardingReveal = RouteRevealPolicy.Everything;
    private string? onboardingCatchUpCheckpointId;
    private bool onboardingUseOpenRouter;
    private RouteContentFilter routeFilter = RouteContentFilter.All;
    private ChatScope chatScope = ChatScope.Current;
    private string? routeDetailStepId;
    private GearPickup? routeDetailPickup;
    private string? selectedPartyMemberId;
    private string? selectedAbilitySetupId;
    private int selectedManualLevel = 1;
    private string? selectedLoadoutMemberId;
    private BuildGear? selectedLoadoutGear;
    private string? buildImportAssignMemberId;
    private int viewedAct = 1;
    private string? actAcceptanceRunId;
    private int actAcceptanceAct;
    private bool acceptsActRouteConsequences;
    private IReadOnlyList<OnboardingStep> onboardingSteps =
        OnboardingFlow.Steps(OnboardingMode.Fresh);

    public MainWindow(
        AssistantController controller,
        StartupTaskService startup,
        GameLauncher launcher,
        AppDataPaths paths,
        OverlayCoordinator overlay,
        CredentialStore credentialStore,
        IOpenRouterClient openRouter,
        BuildImportCoordinator buildImporter)
    {
        this.controller = controller;
        this.startup = startup;
        this.launcher = launcher;
        this.paths = paths;
        this.overlay = overlay;
        this.credentialStore = credentialStore;
        this.openRouter = openRouter;
        this.buildImporter = buildImporter;
        InitializeComponent();
        NowScreen.Attach(this);
        RouteScreen.Attach(this);
        PartyScreen.Attach(this);
        LoadoutScreen.Attach(this);
        ActScreen.Attach(this);
        ChatScreen.Attach(this);
        SettingsScreen.Attach(this);
        Dialogs.Attach(this);
        Onboarding.Attach(this);
        controller.StateChanged += OnControllerStateChanged;
        overlay.StateChanged += OnOverlayStateChanged;
        overlay.OpenRouteRequested += OnOverlayOpenRouteRequested;
        overlay.OpenChatRequested += OnOverlayOpenChatRequested;
        overlay.TaskDoneRequested += OnOverlayTaskDoneRequested;
        overlay.SnoozeRequested += OnOverlaySnoozeRequested;
        overlay.MuteRequested += OnOverlayMuteRequested;
        overlay.PinRequested += OnOverlayPinRequested;
        HeaderPetImage.Source = PetSpriteLoader.Frame(
            PetAnimationModel.Frame(
                isHovered: false,
                hoverElapsed: TimeSpan.Zero,
                pointerLocation: null,
                viewSize: new PetSize(42D, 42D),
                reduceMotion: true));
        Onboarding.OnboardingPetImage.Source = PetSpriteLoader.Frame(
            PetAnimationModel.Frame(
                isHovered: false,
                hoverElapsed: TimeSpan.Zero,
                pointerLocation: null,
                viewSize: new PetSize(46D, 46D),
                reduceMotion: true));
        UpdatePlannerShell();
    }

    public void ShowNow()
    {
        PlannerTabs.SelectedIndex = 0;
    }

    public void ShowSettings()
    {
        PlannerTabs.SelectedIndex = 6;
    }

    public void ShowRoute()
    {
        PlannerTabs.SelectedIndex = 1;
    }

    public void ShowChat()
    {
        PlannerTabs.SelectedIndex = 5;
    }

    public void ShowOverlayPreview()
    {
        overlay.ShowPreview();
    }

    public void LaunchGame()
    {
        try
        {
            launcher.LaunchSteamEdition();
        }
        catch (Exception exception)
        {
            ShowError($"Windows could not open the Steam launch URI: {exception.Message}");
        }
    }

    public void OpenCurrentActMap()
    {
        var act = controller.Run.SelectedAct ?? 1;
        var map = controller.Payload.Acts.FirstOrDefault(summary => summary.Act == act);
        if (map is null)
        {
            ShowError($"No browser map is configured for Act {act}.");
            return;
        }

        try
        {
            launcher.OpenExternalMap(map.MapUrl);
        }
        catch (Exception exception)
        {
            ShowError($"Windows could not open the Act {act} map: {exception.Message}");
        }
    }

    public async Task SwitchRunFromTrayAsync(string runId)
    {
        if (!await controller.SwitchRunAsync(runId))
        {
            ShowError("That run could not be loaded. Its stored bytes were left unchanged.");
        }
    }

    private void RefreshView()
    {
        if (!loaded || controller.Run is null)
        {
            return;
        }

        refreshing = true;
        try
        {
            RefreshHeader();
            RefreshSettingsScreen();
            RefreshNowScreen();
            RefreshRouteScreen();
            RefreshPartyScreen();
            RenderLoadout();
            RenderActLedger();
            RefreshChatScreen();
            RefreshOverlay();
        }
        finally
        {
            refreshing = false;
        }
    }

    private void RefreshHeader()
    {
        if (controller.Run is null)
        {
            return;
        }

        var act = controller.Run.SelectedAct ?? 1;
        HeaderStatusText.Text = PlannerTabs.SelectedIndex switch
        {
            0 => string.IsNullOrWhiteSpace(controller.GoalPresentation.Area)
                ? $"Act {act} · Now"
                : $"Now ▸ {controller.GoalPresentation.Area}",
            2 => "Party",
            3 => "Loadout",
            5 => "Chat",
            6 => "Settings",
            _ => controller.Payload.Acts
                     .FirstOrDefault(summary => summary.Act == act)?.Title ??
                 $"Act {act}",
        };
    }

    private void OnPlannerTabClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string raw } &&
            int.TryParse(raw, out var index))
        {
            PlannerTabs.SelectedIndex = index;
        }
    }

    private void OnPlannerSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        UpdatePlannerShell();
        RefreshHeader();
    }

    private void UpdatePlannerShell()
    {
        var primary = new[]
        {
            NowTabButton,
            RouteTabButton,
            PartyTabButton,
            LoadoutTabButton,
            ActTabButton,
        };
        foreach (var button in primary)
        {
            button.Background = Brushes.Transparent;
            button.BorderBrush = Brushes.Transparent;
            button.Foreground =
                FindResource("BG3MutedParchmentBrush") as Brush ??
                Brushes.Tan;
            button.FontWeight = FontWeights.Normal;
        }

        if (PlannerTabs.SelectedIndex is >= 0 and <= 4)
        {
            var selected = primary[PlannerTabs.SelectedIndex];
            selected.Background =
                FindResource("BG3ProminentActionBrush") as Brush ??
                Brushes.SaddleBrown;
            selected.BorderBrush =
                FindResource("BG3ProminentActionBorderBrush") as Brush ??
                Brushes.Peru;
            selected.Foreground =
                FindResource("BG3ParchmentBrush") as Brush ??
                Brushes.Wheat;
            selected.FontWeight = FontWeights.Bold;
        }

        Width = 420D;
        Height = PlannerTabs.SelectedIndex switch
        {
            0 => NowScreen.NowMoreExpander.IsExpanded ? 550D : 410D,
            2 => 540D,
            3 => 590D,
            _ => 550D,
        };
    }

    private void OnCollapsePlannerClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Hide();
        ShowOverlayPreview();
    }

    private void OnPlannerDragMouseLeftButtonDown(
        object sender,
        MouseButtonEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.ChangedButton != MouseButton.Left ||
            eventArgs.OriginalSource is not DependencyObject source ||
            FindVisualParent<Button>(source) is not null)
        {
            return;
        }

        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            // A lost mouse press simply leaves the window in place.
        }
    }

    private static T? FindVisualParent<T>(DependencyObject? current)
        where T : DependencyObject
    {
        while (current is not null)
        {
            if (current is T match)
            {
                return match;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return null;
    }

    private WalkthroughStep? SelectedRouteStep() =>
        controller.Walkthrough.FirstOrDefault(
            step => step.Id == routeDetailStepId) ??
        (RouteScreen.RouteList.SelectedItem as RoutePlannerRow)?.Step ??
        (RouteScreen.ArchivedRouteList.SelectedItem as ArchivedRouteRow)?.Step;

    private GearPickup? SelectedRoutePickup() =>
        routeDetailPickup ??
        (RouteScreen.RouteList.SelectedItem as RoutePlannerRow)?.Pickup;

    private PartyMember? SelectedPartyMember() =>
        selectedPartyMemberId is null
            ? null
            : (controller.Run.Roster ?? controller.Run.Party)
            .FirstOrDefault(member => member.Id == selectedPartyMemberId);

    private void RefreshOverlay()
    {
        var overlayGoal = controller.CombatCardPinned
            ? controller.GoalPresentation with
            {
                Avoid = string.Join("\n", controller.CombatPinLines),
            }
            : controller.GoalPresentation;
        overlay.Update(
            overlayGoal,
            controller.Preferences,
            controller.Run.SelectedAct ?? 1);
    }

}
