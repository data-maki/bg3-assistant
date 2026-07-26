using System.ComponentModel;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Navigation;
using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;
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
    private string? chatRunId;
    private int chatAct;
    private bool openRouterKeyConfigured;
    private bool refreshing;
    private bool loaded;
    private int onboardingIndex;
    private OnboardingMode onboardingMode = OnboardingMode.Fresh;
    private RunDifficulty onboardingDifficulty = RunDifficulty.Honour;
    private RouteRevealPolicy onboardingReveal = RouteRevealPolicy.Everything;
    private RouteContentFilter routeFilter = RouteContentFilter.All;
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
        controller.StateChanged += OnControllerStateChanged;
        overlay.StateChanged += OnOverlayStateChanged;
        overlay.OpenRouteRequested += OnOverlayOpenRouteRequested;
        overlay.OpenChatRequested += OnOverlayOpenChatRequested;
        overlay.TaskDoneRequested += OnOverlayTaskDoneRequested;
        overlay.SnoozeRequested += OnOverlaySnoozeRequested;
        overlay.MuteRequested += OnOverlayMuteRequested;
        overlay.PinRequested += OnOverlayPinRequested;
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

    private async void OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (loaded)
        {
            return;
        }

        loaded = true;
        OverlayDensityPicker.ItemsSource = Enum.GetValues<OverlayDensity>();
        RouteFilterPicker.ItemsSource = Enum.GetValues<RouteContentFilter>();
        RouteFilterPicker.SelectedItem = routeFilter;
        ChatScopePicker.ItemsSource = Enum.GetValues<ChatScope>();
        ChatScopePicker.SelectedItem = ChatScope.Current;
        PackageStatusText.Text = PackageIdentity.TryGetFullName() is { } fullName
            ? $"Installed package: {fullName}"
            : "Unpackaged development launch. Packaged startup is unavailable.";
        StoragePathText.Text = $"Local state: {paths.Root}";
        RefreshCredentialStatus();
        await RefreshStartupAsync();
        RefreshView();
        if (controller.Preferences.OnboardingVersion < OnboardingFlow.Version)
        {
            StartOnboarding();
        }
    }

    private void OnClosing(object? sender, CancelEventArgs eventArgs)
    {
        _ = sender;
        if (Application.Current is App app && !app.ExitRequested)
        {
            eventArgs.Cancel = true;
            Hide();
            app.ShowTrayNotice();
        }
    }

    private void OnControllerStateChanged(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dispatcher.Invoke(RefreshView);
    }

    private void OnOverlayStateChanged(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        Dispatcher.Invoke(RefreshHeader);
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
            EnsureChatContext();
            RunPicker.ItemsSource = controller.Runs;
            RunPicker.SelectedItem = controller.Runs.FirstOrDefault(run => run.IsActive);
            if (!RunNameTextBox.IsKeyboardFocusWithin)
            {
                RunNameTextBox.Text = controller.Run.Name ?? "Honor Run";
            }

            var goal = controller.GoalPresentation;
            GoalTitleText.Text = goal.Title;
            GoalMetaText.Text = string.IsNullOrEmpty(goal.Area)
                ? $"Act {controller.Run.SelectedAct ?? 1} · L{goal.MinimumLevel}+"
                : $"{goal.Area} · L{goal.MinimumLevel}+ · {goal.Danger.ToUpperInvariant()}";
            GoalAvoidText.Text = goal.Avoid;
            var readiness = controller.Readiness;
            ReadinessText.Text = readiness is null
                ? "No fight gate is attached to this activity."
                : $"{readiness.Status.ToUpperInvariant()} · " +
                  (readiness.Blockers.FirstOrDefault() ??
                   readiness.Warnings.FirstOrDefault() ??
                   readiness.NextActions.FirstOrDefault() ??
                   "Ready.");
            if (controller.WarningsSuppressed && readiness is not null)
            {
                ReadinessText.Text += " · warnings suppressed";
            }
            var checkpoint = controller.CurrentCheckpoint;
            MuteButton.Content = checkpoint is not null &&
                                 controller.Run.MutedCheckpointIds?.Contains(checkpoint.Id) == true
                ? "Unmute warnings"
                : "Mute warnings";
            ClearTargetButton.Visibility = controller.TargetContext is null
                ? Visibility.Collapsed
                : Visibility.Visible;
            PinFightButton.Content = controller.CombatCardPinned
                ? "Unpin fight"
                : "Pin fight";

            var selectedRouteStepId =
                (RouteList.SelectedItem as RoutePlannerRow)?.Step?.Id;
            var selectedPickupId =
                (RouteList.SelectedItem as RoutePlannerRow)?.Pickup?.Id;
            var routePresentation = RoutePlannerRules.Present(
                controller.Walkthrough,
                controller.Run.WalkthroughProgress,
                controller.Run.WalkthroughOutcomes,
                controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything,
                controller.RoutePickups,
                routeFilter,
                controller.CurrentStep,
                controller.LowestPartyLevel);
            RouteProgressBar.Value = routePresentation.Progress;
            RouteProgressText.Text =
                $"{routePresentation.ArchivedCount}/{routePresentation.TotalCount} resolved";
            RouteGateText.Text = (controller.Run.SelectedAct ?? 1) == 3
                ? "Final act - no next-act gate."
                : controller.CurrentActConsequences.Count == 0
                    ? $"Act {(controller.Run.SelectedAct ?? 1) + 1} gate: ready."
                    : $"Act {(controller.Run.SelectedAct ?? 1) + 1} gate: " +
                      $"{controller.CurrentActConsequences.Count} consequence" +
                      (controller.CurrentActConsequences.Count == 1 ? string.Empty : "s") +
                      " remain.";
            RouteSpoilerText.Text = routePresentation.SpoilerLight
                ? "Spoiler-light - showing only the next 3 route tasks."
                : string.Empty;
            RouteDeadlineList.ItemsSource = controller.Payload.TimedEvents;
            RouteDeadlinesExpander.Visibility =
                controller.Payload.TimedEvents.Count == 0
                    ? Visibility.Collapsed
                    : Visibility.Visible;
            RouteList.ItemsSource = routePresentation.Rows;
            ArchivedRouteList.ItemsSource = routePresentation.Archived;
            RouteList.SelectedItem = routePresentation.Rows.FirstOrDefault(
                                         row => row.Step?.Id == selectedRouteStepId) ??
                                     routePresentation.Rows.FirstOrDefault(
                                         row => row.Pickup?.Id == selectedPickupId) ??
                                     routePresentation.Rows.FirstOrDefault(
                                         row => row.Step?.Id == controller.CurrentStep?.Id) ??
                                     routePresentation.Rows.FirstOrDefault(
                                         row => row.IsSelectable);

            PartyGrid.ItemsSource = controller.Run.Roster ?? controller.Run.Party;
            BuildList.ItemsSource = controller.Builds;
            var selectedMemberId = (BuildMemberPicker.SelectedItem as PartyMember)?.Id;
            BuildMemberPicker.ItemsSource = controller.ActiveParty;
            BuildMemberPicker.SelectedItem =
                controller.ActiveParty.FirstOrDefault(member => member.Id == selectedMemberId) ??
                controller.ActiveParty.FirstOrDefault();
            if (BuildList.SelectedItem is not BuildSummary)
            {
                BuildList.SelectedItem = controller.Builds.FirstOrDefault();
            }

            var act = controller.Run.SelectedAct ?? 1;
            var actSummary = controller.Payload.Acts.FirstOrDefault(item => item.Act == act);
            ActTitleText.Text = actSummary?.Title ?? $"Act {act}";
            ActAvailabilityText.Text = controller.Payload.RouteAvailable
                ? "Reviewed route guidance is available."
                : CurrentGoalRules.ActTwoUnavailableMessage;
            ActCountsText.Text =
                $"{controller.Payload.Walkthrough.Count} route steps · " +
                $"{controller.Payload.Checkpoints.Count} fight checkpoints · " +
                $"{controller.Payload.Builds.Count} reviewed builds";
            ActGateText.Text = controller.ActTransitionBlockedReason ??
                               (controller.CurrentActConsequences.Count > 0
                                   ? string.Join("\n", controller.CurrentActConsequences)
                                   : "The act gate is ready. Advancing locks this act ledger.");
            var selectedActGearKey =
                (ActGearList.SelectedItem as ActGearRow)?.Gear.ItemKey;
            var actGearRows = controller.CurrentActGear
                .Select(
                    gear => new ActGearRow(
                        gear,
                        ActTransitionRules.ReviewStatus(
                            controller.Run,
                            gear,
                            act)?.ToString() ?? "Needs review"))
                .ToList();
            ActGearList.ItemsSource = actGearRows;
            ActGearList.SelectedItem =
                actGearRows.FirstOrDefault(row => row.Gear.ItemKey == selectedActGearKey) ??
                actGearRows.FirstOrDefault();
            AdvanceActButton.IsEnabled = controller.ActTransitionBlockedReason is null;

            ShowOverlayCheckBox.IsChecked =
                controller.Preferences.ShowOverlayWhileGameRuns;
            OverlayDensityPicker.SelectedItem = controller.Preferences.OverlayDensity;
            ReducedMotionCheckBox.IsChecked = controller.Preferences.ReducedMotion;

            ChatAvailabilityText.Text = controller.Payload.RouteAvailable
                ? "Typed OpenRouter chat is session-only; messages and prompts are never saved."
                : CurrentGoalRules.ActTwoUnavailableMessage +
                  ". Reviewed route chat is unavailable for this act.";
            RenderChatHistory();
            SendChatButton.IsEnabled =
                controller.Payload.RouteAvailable &&
                openRouterKeyConfigured &&
                chatCancellation is null;
            ImportBuildButton.IsEnabled =
                openRouterKeyConfigured &&
                importCancellation is null;
            TestOpenRouterButton.IsEnabled =
                openRouterKeyConfigured &&
                keyTestCancellation is null;

            DiagnosticsText.Text =
                $"Guide version: {controller.Guide.GuideVersion}\n" +
                $"Run id: {controller.Run.Id}\n" +
                $"Database: {paths.Database}\n" +
                $"Package: {(PackageIdentity.IsPackaged ? "MSIX" : "unpackaged development")}\n" +
                $"Supported windows: bg3.exe, bg3_dx11.exe\n" +
                $"Detected window: {overlay.GameStatus}\n" +
                $"Recovery: {controller.RecoveryNotice ?? "not needed"}\n" +
                $"OpenRouter: {(openRouterKeyConfigured ? "key configured" : "not configured")} · {OpenRouterClient.Model}\n" +
                "Game memory, files, saves, injection, hooks, services, and elevation: unused";
            FooterStatusText.Text = controller.RecoveryNotice ?? "Local guide and run state ready.";
            var overlayGoal = controller.CombatCardPinned
                ? controller.GoalPresentation with
                {
                    Avoid = string.Join("\n", controller.CombatPinLines),
                }
                : controller.GoalPresentation;
            overlay.Update(overlayGoal, controller.Preferences);
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

        HeaderStatusText.Text =
            $"{controller.Run.Name ?? "Honor Run"} · {overlay.GameStatus}";
    }

    private void OnRouteSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (RouteList.SelectedItem is not RoutePlannerRow row)
        {
            RouteStepTitleText.Text = string.Empty;
            RouteStepMetaText.Text = string.Empty;
            RouteStepSummaryText.Text = string.Empty;
            RouteStepAvoidText.Text = string.Empty;
            RouteStepWhyText.Text = string.Empty;
            return;
        }

        if (row.Pickup is { } pickup)
        {
            ShowRouteGear(pickup);
            return;
        }

        if (row.Step is not { } step)
        {
            return;
        }

        RouteStepPanel.Visibility = Visibility.Visible;
        RouteGearPanel.Visibility = Visibility.Collapsed;
        RouteStepTitleText.Text = step.Title;
        RouteStepMetaText.Text =
            $"{step.Phase} · L{step.MinimumLevel}+ · {StepEncounterRules.Classify(step).Label()}";
        RouteStepSummaryText.Text = step.Summary;
        RouteStepAvoidText.Text = string.IsNullOrEmpty(step.Avoid)
            ? string.Empty
            : $"Avoid: {step.Avoid}";
        RouteStepWhyText.Text = step.Why;
        RouteStepRewardsText.Text = step.Rewards.Count == 0
            ? string.Empty
            : $"Rewards: {string.Join(" - ", step.Rewards)}";
        var prerequisites = step.Prerequisites
            .Concat(step.Dependencies.Select(dependency => dependency.StepId))
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(
                value =>
                    controller.Walkthrough.FirstOrDefault(candidate => candidate.Id == value)
                        ?.Title ?? value)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        RouteStepPrerequisitesText.Text = prerequisites.Count == 0
            ? string.Empty
            : $"First: {string.Join(" - ", prerequisites)}";
        RouteStepCompletionText.Text = step.CompletionChecks.Count == 0
            ? string.Empty
            : $"Done when: {string.Join(" - ", step.CompletionChecks)}";
        var recordedOutcome =
            controller.Run.WalkthroughOutcomes?.GetValueOrDefault(step.Id);
        RouteStepOutcomeText.Text = recordedOutcome is null
            ? string.Empty
            : $"Recorded outcome: {recordedOutcome}";
        RouteDecisionGroup.Visibility =
            step.Decision is null ? Visibility.Collapsed : Visibility.Visible;
        if (step.Decision is { } decision)
        {
            var options = new[] { decision.Recommended }
                .Concat(decision.Alternatives)
                .ToList();
            RouteDecisionText.Text =
                $"{decision.Prompt}\n\n" +
                string.Join(
                    "\n\n",
                    options.Select(
                        option =>
                            $"{option.Label}\n" +
                            $"Benefits: {string.Join("; ", option.Benefits)}\n" +
                            $"Costs: {string.Join("; ", option.Costs)}"));
            RouteOutcomePicker.ItemsSource = options;
            RouteOutcomePicker.SelectedItem =
                options.FirstOrDefault(option => option.Label == recordedOutcome) ??
                options.FirstOrDefault();
        }
        else
        {
            RouteDecisionText.Text = string.Empty;
            RouteOutcomePicker.ItemsSource = null;
        }

        var incident = RunProgressRules.IncidentProtocol(step, controller.Route);
        RouteIncidentGroup.Visibility =
            incident is null ? Visibility.Collapsed : Visibility.Visible;
        RouteIncidentText.Text = incident is null
            ? string.Empty
            : $"Trigger: {incident.Trigger}\n" +
              $"Safe actions: {string.Join("; ", incident.SafeActions)}\n" +
              $"Never: {incident.Never}\n" +
              $"Escape: {incident.Escape}\n" +
              $"Honor change: {incident.HonorDelta}";
        RouteRiskGroup.Visibility =
            step.RiskReward is null ? Visibility.Collapsed : Visibility.Visible;
        RouteRiskText.Text = step.RiskReward is null
            ? string.Empty
            : $"Reward: {step.RiskReward.Reward}\n" +
              $"Risk: {step.RiskReward.Risk}\n" +
              $"Skip cost: {step.RiskReward.SkipCost}\n" +
              $"Return by: {step.RiskReward.ReturnBy}";
        RouteSourceButton.IsEnabled =
            GameLauncher.TryCreateHttpUri(step.SourceUrl, out _);
    }

    private void ShowRouteGear(GearPickup pickup)
    {
        RouteStepPanel.Visibility = Visibility.Collapsed;
        RouteGearPanel.Visibility = Visibility.Visible;
        var gear = pickup.Gear;
        RouteGearTitleText.Text = gear.Item;
        RouteGearMetaText.Text =
            $"For {pickup.MemberName} - {gear.Slot} - {gear.Priority} - {gear.Region}";
        RouteGearEffectText.Text = string.IsNullOrWhiteSpace(gear.Effect)
            ? "No separate effect text is recorded in this guide version."
            : gear.Effect;
        RouteGearAcquisitionText.Text = $"Acquire: {GearLogic.AcquireText(gear)}";
        RouteGearWhyText.Text = gear.Why;
        RouteGearRequirementText.Text = gear.Requirement ?? string.Empty;
    }

    private void OnRouteFilterChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            RouteFilterPicker.SelectedItem is not RouteContentFilter selected)
        {
            return;
        }

        routeFilter = selected;
        RefreshView();
    }

    private void OnArchivedRouteSelectionChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (ArchivedRouteList.SelectedItem is not ArchivedRouteRow archived)
        {
            return;
        }

        RouteStepPanel.Visibility = Visibility.Visible;
        RouteGearPanel.Visibility = Visibility.Collapsed;
        RouteStepTitleText.Text = archived.Step.Title;
        RouteStepMetaText.Text =
            $"{archived.Disposition} - {archived.Step.Phase} - {archived.Step.Area}";
        RouteStepSummaryText.Text = archived.Step.Summary;
        RouteStepAvoidText.Text = archived.Step.Avoid;
        RouteStepWhyText.Text = archived.Step.Why;
    }

    private async void OnRecordOutcomeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step &&
            RouteOutcomePicker.SelectedItem is DecisionOption option)
        {
            await controller.ResolveOutcomeAsync(step, option.Label);
        }
    }

    private void OnOpenRouteSourceClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is not { } step)
        {
            return;
        }

        OpenExternalLink(step.SourceUrl, "reviewed route source");
    }

    private async void OnTrackRouteGearClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is { } pickup)
        {
            await controller.SetGearTargetAsync(pickup.MemberId, pickup.Gear);
        }
    }

    private async void OnMarkRouteGearObtainedClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is { } pickup)
        {
            await controller.MarkGearObtainedAsync(pickup.MemberId, pickup.Gear);
        }
    }

    private void OnOpenRouteGearLinkClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRoutePickup() is not { } pickup)
        {
            return;
        }

        OpenExternalLink(
            !string.IsNullOrWhiteSpace(pickup.Gear.Wiki)
                ? pickup.Gear.Wiki
                : pickup.Gear.Source,
            "item source");
    }

    private WalkthroughStep? SelectedRouteStep() =>
        (RouteList.SelectedItem as RoutePlannerRow)?.Step ??
        (ArchivedRouteList.SelectedItem as ArchivedRouteRow)?.Step;

    private GearPickup? SelectedRoutePickup() =>
        (RouteList.SelectedItem as RoutePlannerRow)?.Pickup;

    private void OpenExternalLink(string? value, string label)
    {
        try
        {
            launcher.OpenExternalMap(value ?? string.Empty);
        }
        catch (Exception exception)
        {
            ShowError($"Windows could not open the {label}: {exception.Message}");
        }
    }

    private void OnBuildSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (BuildList.SelectedItem is not BuildSummary build)
        {
            BuildTitleText.Text = string.Empty;
            BuildRoleText.Text = string.Empty;
            BuildPatternText.Text = string.Empty;
            BuildGearList.ItemsSource = null;
            return;
        }

        BuildTitleText.Text = build.Name;
        BuildRoleText.Text = $"{build.Role} · {build.FinalSplit}";
        BuildPatternText.Text = build.PlayPattern;
        BuildGearList.ItemsSource = build.Gear
            .OrderBy(gear => gear.Act)
            .ThenBy(gear => GearLogic.PriorityRank(gear.Priority))
            .ThenBy(gear => gear.Item);
    }

    private async void OnRunSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (refreshing ||
            RunPicker.SelectedItem is not SavedRun selected ||
            selected.Id == controller.Run.Id)
        {
            return;
        }

        if (!await controller.SwitchRunAsync(selected.Id))
        {
            ShowError("That run could not be loaded. Its stored bytes were left unchanged.");
        }
    }

    private async void OnNewRunClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var name = $"Honor Run {DateTime.Now:yyyy-MM-dd HH:mm}";
        await controller.CreateRunAsync(
            name,
            controller.Run.Difficulty ?? RunDifficulty.Honour,
            controller.Run.RouteRevealPolicy ?? RouteRevealPolicy.Everything);
    }

    private async void OnRenameRunClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (!string.IsNullOrWhiteSpace(RunNameTextBox.Text))
        {
            await controller.RenameRunAsync(RunNameTextBox.Text);
        }
    }

    private void OnLaunchGameClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        LaunchGame();
    }

    private void OnShowOverlayClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        ShowOverlayPreview();
    }

    private async void OnCompleteCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await CompleteCurrentTaskAsync();
    }

    private async Task CompleteCurrentTaskAsync()
    {
        if (controller.CurrentStep?.Decision is not null)
        {
            PlannerTabs.SelectedIndex = 1;
            RouteList.SelectedItem = controller.CurrentStep;
            FooterStatusText.Text = "Choose the outcome on the route step before marking it done.";
            return;
        }

        await controller.CompleteCurrentGoalAsync();
    }

    private void OnOverlayOpenRouteRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        (Application.Current as App)?.ShowMainWindow();
        ShowRoute();
    }

    private void OnOverlayOpenChatRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        (Application.Current as App)?.ShowMainWindow();
        ShowChat();
    }

    private async void OnOverlayTaskDoneRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await CompleteCurrentTaskAsync();
    }

    private void OnOverlaySnoozeRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        controller.SnoozeWarnings();
    }

    private async void OnOverlayMuteRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ToggleMuteCurrentAsync();
    }

    private void OnOverlayPinRequested(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (controller.CombatCardPinned)
        {
            controller.UnpinFight();
        }
        else if (!controller.PinCurrentFight())
        {
            ShowError("Resolve readiness blockers before pinning this fight.");
        }
    }

    private async void OnSkipCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await ApplyDispositionWithConfirmationAsync(CheckpointDisposition.Skipped);
    }

    private async void OnRevisitCurrentClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
    }

    private async void OnFollowRouteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.FollowRecommendationAsync();
    }

    private async void OnMuteClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ToggleMuteCurrentAsync();
    }

    private async void OnClearTargetClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await controller.ClearGearTargetAsync();
    }

    private void OnPinFightClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (controller.CombatCardPinned)
        {
            controller.UnpinFight();
            return;
        }

        if (!controller.PinCurrentFight())
        {
            ShowError("Resolve readiness blockers before pinning this fight.");
        }
    }

    private void OnSnoozeClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        controller.SnoozeWarnings();
    }

    private async void OnFocusSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step)
        {
            await controller.FocusStepAsync(step);
            PlannerTabs.SelectedIndex = 0;
        }
    }

    private async void OnCompleteSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is not { } step)
        {
            return;
        }

        await controller.FocusStepAsync(step);
        if (step.Decision is null)
        {
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Completed);
            return;
        }

        var options = new[] { step.Decision.Recommended }
            .Concat(step.Decision.Alternatives)
            .ToList();
        var outcome = options.FirstOrDefault()?.Label;
        if (outcome is not null &&
            MessageBox.Show(
                this,
                $"Record the reviewed option “{outcome}”?\n\n" +
                "If something else happened, keep the step open until the outcome can be selected.",
                "Record route outcome",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            await controller.ResolveOutcomeAsync(step, outcome);
        }
    }

    private async void OnSkipSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (SelectedRouteStep() is { } step)
        {
            await controller.FocusStepAsync(step);
            await ApplyDispositionWithConfirmationAsync(CheckpointDisposition.Skipped);
        }
    }

    private async void OnRevisitSelectedStepClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (ArchivedRouteList.SelectedItem is ArchivedRouteRow archivedRow)
        {
            await controller.FocusStepAsync(archivedRow.Step);
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
        }
        else if ((RouteList.SelectedItem as RoutePlannerRow)?.Step is { } step)
        {
            await controller.FocusStepAsync(step);
            await controller.SetCurrentDispositionAsync(CheckpointDisposition.Pending);
        }
    }

    private async Task ApplyDispositionWithConfirmationAsync(
        CheckpointDisposition disposition)
    {
        var request = controller.RequestDisposition(disposition);
        if (request.RequiresConfirmation &&
            MessageBox.Show(
                this,
                request.ConfirmationMessage,
                "Confirm route change",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning) != MessageBoxResult.OK)
        {
            return;
        }

        await controller.SetCurrentDispositionAsync(disposition);
    }

    private async void OnLevelDownClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyGrid.SelectedItem is PartyMember member)
        {
            await controller.SetPartyLevelAsync(member.Id, member.Level - 1);
        }
    }

    private async void OnLevelUpClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyGrid.SelectedItem is PartyMember member)
        {
            await controller.SetPartyLevelAsync(member.Id, member.Level + 1);
        }
    }

    private async void OnSendToCampClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyGrid.SelectedItem is PartyMember member &&
            !await controller.SetRosterStatusAsync(member.Id, RosterStatus.Camp))
        {
            ShowError("That roster status could not be applied.");
        }
    }

    private async void OnMakeActiveClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (PartyGrid.SelectedItem is PartyMember member &&
            !await controller.SetRosterStatusAsync(member.Id, RosterStatus.Active))
        {
            ShowError(
                "The active party is full or this member is unavailable. " +
                "Send someone to camp or confirm the member's story status first.");
        }
    }

    private async void OnAssignBuildClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (BuildList.SelectedItem is not BuildSummary build ||
            BuildMemberPicker.SelectedItem is not PartyMember member)
        {
            return;
        }

        if (PartyPlanningRules.BuildReplacementNeedsConfirmation(controller.Run, member) &&
            MessageBox.Show(
                this,
                "Replacing this build clears run-specific equipment and temporary setup choices. Continue?",
                "Replace build",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning) != MessageBoxResult.OK)
        {
            return;
        }

        await controller.AssignBuildAsync(member.Id, build.Id);
    }

    private async void OnClearBuildClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (BuildMemberPicker.SelectedItem is PartyMember member)
        {
            await controller.AssignBuildAsync(member.Id, null);
        }
    }

    private async void OnTrackGearClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (BuildGearList.SelectedItem is not BuildGear gear ||
            BuildMemberPicker.SelectedItem is not PartyMember member)
        {
            return;
        }

        if (!await controller.SetGearTargetAsync(member.Id, gear))
        {
            ShowError(
                "Assign this reviewed build to the selected active character and choose an item from the current act first.");
            return;
        }

        PlannerTabs.SelectedIndex = 0;
    }

    private async void OnActGearObtainedClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (ActGearList.SelectedItem is ActGearRow row)
        {
            await controller.SetActGearReviewAsync(
                row.Gear,
                ActGearReviewStatus.Obtained);
        }
    }

    private async void OnActGearMissedClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (ActGearList.SelectedItem is ActGearRow row)
        {
            await controller.SetActGearReviewAsync(
                row.Gear,
                ActGearReviewStatus.Missed);
        }
    }

    private async void OnAdvanceActClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var consequences = controller.CurrentActConsequences;
        var accept = consequences.Count == 0 ||
                     MessageBox.Show(
                         this,
                         "Advancing will lock this act with these unresolved consequences:\n\n" +
                         string.Join("\n", consequences),
                         "Lock act ledger",
                         MessageBoxButton.OKCancel,
                         MessageBoxImage.Warning) == MessageBoxResult.OK;
        if (!accept || !await controller.AdvanceActAsync(accept))
        {
            if (accept)
            {
                ShowError(
                    controller.ActTransitionBlockedReason ??
                    "The act could not be advanced.");
            }

            return;
        }

        PlannerTabs.SelectedIndex = 4;
    }

    private void OnOpenActMapClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        OpenCurrentActMap();
    }

    private async void OnOverlayPreferenceChanged(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await PersistOverlayPreferencesAsync();
    }

    private async void OnOverlayPreferenceChanged(
        object sender,
        SelectionChangedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await PersistOverlayPreferencesAsync();
    }

    private async Task PersistOverlayPreferencesAsync()
    {
        if (refreshing ||
            OverlayDensityPicker.SelectedItem is not OverlayDensity density)
        {
            return;
        }

        await controller.UpdatePreferencesAsync(
            controller.Preferences with
            {
                OverlayDensity = density,
                ShowOverlayWhileGameRuns = ShowOverlayCheckBox.IsChecked == true,
                ReducedMotion = ReducedMotionCheckBox.IsChecked == true,
            });
    }

    private async void OnEnableStartupClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        ApplyStartupStatus(await startup.RequestEnableFromUserActionAsync());
    }

    private async void OnDisableStartupClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        ApplyStartupStatus(await startup.DisableFromUserActionAsync());
    }

    private async Task RefreshStartupAsync()
    {
        ApplyStartupStatus(await startup.GetStatusAsync());
    }

    private void ApplyStartupStatus(StartupRegistrationStatus status)
    {
        StartupStatusText.Text = status.Message;
        EnableStartupButton.IsEnabled = status.CanRequestEnable;
        DisableStartupButton.IsEnabled =
            status.State == StartupRegistrationState.Enabled;
    }

    private async void OnSendChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        await SendChatAsync();
    }

    private async void OnQuickChatClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = eventArgs;
        if (sender is Button { Tag: string prompt })
        {
            await SendChatAsync(prompt);
        }
    }

    private async void OnChatDraftKeyDown(object sender, KeyEventArgs eventArgs)
    {
        _ = sender;
        if (eventArgs.Key == Key.Enter &&
            Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
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
        ChatStatusText.Text = "Session chat cleared.";
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
            ChatStatusText.Text =
                $"{CurrentGoalRules.ActTwoUnavailableMessage}. Typed route chat is unavailable.";
            return;
        }

        var question = (quickPrompt ?? ChatDraftTextBox.Text).Trim();
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
            ChatStatusText.Text =
                $"Windows Credential Manager could not read the OpenRouter key: {exception.Message}";
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            OpenRouterKeyStatusText.Text =
                "No key is saved. Add one in Settings to use typed chat.";
            ChatStatusText.Text =
                "Configure an OpenRouter key in Settings before sending typed chat.";
            PlannerTabs.SelectedIndex = 6;
            UpdateNetworkButtons();
            return;
        }

        var requestedRunId = controller.Run.Id;
        var requestedAct = controller.Run.SelectedAct ?? 1;
        var scope = ChatScopePicker.SelectedItem is ChatScope selectedScope
            ? selectedScope
            : ChatScope.Current;
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
                scope,
                history);
        }
        catch (InvalidOperationException exception)
        {
            ChatStatusText.Text = exception.Message;
            return;
        }

        chatLines.Add(new ChatLineRow("user", question, [], IsError: false));
        ChatDraftTextBox.Clear();
        RenderChatHistory();
        chatCancellation = new CancellationTokenSource();
        ChatStatusText.Text =
            $"Waiting for {OpenRouterClient.ModelDisplayName}…";
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
                ChatStatusText.Text =
                    $"Answered by the pinned {OpenRouterClient.ModelDisplayName} model.";
                RenderChatHistory();
            }
        }
        catch (OperationCanceledException)
        {
            ChatStatusText.Text = "Chat request cancelled.";
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
        ChatStatusText.Text =
            "OpenRouter could not answer. The local Now and Route tabs remain available.";
        RenderChatHistory();
    }

    private void OnSaveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var key = OpenRouterKeyPasswordBox.Password.Trim();
        OpenRouterKeyPasswordBox.Clear();
        if (key.Length == 0)
        {
            OpenRouterKeyStatusText.Text =
                "Enter an OpenRouter API key before saving.";
            return;
        }

        try
        {
            credentialStore.Save(key);
            openRouterKeyConfigured = true;
            OpenRouterKeyStatusText.Text =
                "Key saved for this Windows user in Windows Credential Manager.";
        }
        catch (Exception exception)
        {
            openRouterKeyConfigured = false;
            OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not save the key: {exception.Message}";
        }

        UpdateNetworkButtons();
    }

    private async void OnTestOpenRouterClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (keyTestCancellation is not null)
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
            OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not read the key: {exception.Message}";
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            OpenRouterKeyStatusText.Text = "No OpenRouter key is saved.";
            UpdateNetworkButtons();
            return;
        }

        keyTestCancellation = new CancellationTokenSource();
        OpenRouterKeyStatusText.Text =
            $"Testing the pinned {OpenRouterClient.ModelDisplayName} model…";
        UpdateNetworkButtons();
        try
        {
            var result = await openRouter.CompleteAsync(
                apiKey,
                [
                    new OpenRouterMessage(
                        "system",
                        "Return strict JSON matching the supplied schema. Put the single word OK in answer."),
                    new OpenRouterMessage("user", "Connection test."),
                ],
                ChatPromptBuilder.ResponseSchema,
                "connection_test",
                512,
                keyTestCancellation.Token);
            _ = ChatPromptBuilder.DecodeAnswer(result);
            openRouterKeyConfigured = true;
            OpenRouterKeyStatusText.Text =
                $"Connected successfully to {OpenRouterClient.Model}.";
        }
        catch (OperationCanceledException)
        {
            OpenRouterKeyStatusText.Text = "OpenRouter connection test cancelled.";
        }
        catch (Exception exception)
        {
            OpenRouterKeyStatusText.Text =
                $"OpenRouter connection test failed: {exception.Message}";
        }
        finally
        {
            keyTestCancellation.Dispose();
            keyTestCancellation = null;
            UpdateNetworkButtons();
        }
    }

    private void OnRemoveOpenRouterKeyClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        try
        {
            var removed = credentialStore.Delete();
            openRouterKeyConfigured = false;
            OpenRouterKeyPasswordBox.Clear();
            OpenRouterKeyStatusText.Text = removed
                ? "OpenRouter key removed from Windows Credential Manager."
                : "No saved OpenRouter key was present.";
        }
        catch (Exception exception)
        {
            OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager could not remove the key: {exception.Message}";
        }

        UpdateNetworkButtons();
    }

    private async void OnImportBuildClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (importCancellation is not null)
        {
            return;
        }

        var rawUrl = BuildImportUrlTextBox.Text.Trim();
        if (rawUrl.Length == 0)
        {
            BuildImportStatusText.Text = "Enter a public HTTPS build URL.";
            return;
        }

        string? apiKey;
        try
        {
            apiKey = credentialStore.Read();
        }
        catch (Exception exception)
        {
            BuildImportStatusText.Text =
                $"Windows Credential Manager could not read the OpenRouter key: {exception.Message}";
            return;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            BuildImportStatusText.Text =
                "Save an OpenRouter key in Settings before importing a build.";
            UpdateNetworkButtons();
            return;
        }

        importCancellation = new CancellationTokenSource();
        BuildImportStatusText.Text =
            "Downloading and validating the public source, then asking the pinned model…";
        UpdateNetworkButtons();
        try
        {
            var imported = await buildImporter.ImportAsync(
                rawUrl,
                apiKey,
                importCancellation.Token);
            await controller.SaveImportedBuildAsync(
                imported,
                importCancellation.Token);
            BuildImportUrlTextBox.Clear();
            BuildImportStatusText.Text =
                $"Imported “{imported.Name}”. Verify every choice in game before relying on it.";
            BuildList.SelectedItem =
                controller.Builds.FirstOrDefault(build => build.Id == imported.Id);
        }
        catch (OperationCanceledException)
        {
            BuildImportStatusText.Text = "Build import cancelled.";
        }
        catch (Exception exception) when (
            exception is
                PublicNetworkException or
                BuildImportSourceException or
                OpenRouterException or
                BuildImportProcessingException)
        {
            BuildImportStatusText.Text = $"Build import failed: {exception.Message}";
        }
        finally
        {
            importCancellation.Dispose();
            importCancellation = null;
            UpdateNetworkButtons();
        }
    }

    private async void OnDeleteImportedBuildClick(
        object sender,
        RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (BuildList.SelectedItem is not BuildSummary selected ||
            controller.ImportedBuilds.All(imported => imported.Id != selected.Id))
        {
            BuildImportStatusText.Text =
                "Select an imported build before removing it.";
            return;
        }

        if (controller.ActiveParty.Any(member => member.BuildId == selected.Id))
        {
            BuildImportStatusText.Text =
                "Clear this build from every active character before removing it.";
            return;
        }

        var confirmation = MessageBox.Show(
            this,
            $"Remove the saved imported build “{selected.Name}”?",
            "Remove imported build",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (confirmation != MessageBoxResult.Yes)
        {
            return;
        }

        BuildImportStatusText.Text = await controller.DeleteImportedBuildAsync(selected.Id)
            ? "Imported build removed."
            : "The imported build could not be removed.";
    }

    private void RefreshCredentialStatus()
    {
        try
        {
            openRouterKeyConfigured =
                !string.IsNullOrWhiteSpace(credentialStore.Read());
            OpenRouterKeyStatusText.Text = openRouterKeyConfigured
                ? "A key is saved for this Windows user in Windows Credential Manager."
                : "No OpenRouter key is saved.";
        }
        catch (Exception exception)
        {
            openRouterKeyConfigured = false;
            OpenRouterKeyStatusText.Text =
                $"Windows Credential Manager is unavailable: {exception.Message}";
        }

        UpdateNetworkButtons();
    }

    private void UpdateNetworkButtons()
    {
        if (!loaded)
        {
            return;
        }

        SendChatButton.IsEnabled =
            openRouterKeyConfigured &&
            controller.Payload.RouteAvailable &&
            chatCancellation is null;
        ImportBuildButton.IsEnabled =
            openRouterKeyConfigured &&
            importCancellation is null;
        TestOpenRouterButton.IsEnabled =
            openRouterKeyConfigured &&
            keyTestCancellation is null;
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
            ChatStatusText.Text =
                "Chat context changed. The prior session history was cleared.";
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
        if (chatLines.Count == 0)
        {
            document.Blocks.Add(
                new Paragraph(
                    new Run(
                        "Ask about this run state. Guide facts and unknowns stay labelled."))
                {
                    Foreground =
                        (System.Windows.Media.Brush)FindResource("SecondaryTextBrush"),
                });
        }

        foreach (var line in chatLines)
        {
            var paragraph = new Paragraph
            {
                Margin = new Thickness(0, 0, 0, 12),
            };
            paragraph.Inlines.Add(
                new Bold(
                    new Run(
                        line.Role == "user"
                            ? "YOU\n"
                            : line.IsError
                                ? "OPENROUTER ERROR\n"
                                : "ASSISTANT\n")));
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
                    (System.Windows.Media.Brush)FindResource("DangerBrush");
            }

            document.Blocks.Add(paragraph);
        }

        ChatHistoryBox.Document = document;
        ChatHistoryBox.ScrollToEnd();
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
            ChatStatusText.Text = "The selected source link could not be opened.";
        }
    }

    private void StartOnboarding()
    {
        onboardingIndex = 0;
        onboardingMode = OnboardingMode.Fresh;
        onboardingSteps = OnboardingFlow.Steps(onboardingMode);
        OnboardingPanel.Visibility = Visibility.Visible;
        ShowOnboardingStep();
    }

    private void ShowOnboardingStep()
    {
        var step = onboardingSteps[onboardingIndex];
        OnboardingBackButton.IsEnabled = onboardingIndex > 0;
        OnboardingNextButton.Content =
            onboardingIndex == onboardingSteps.Count - 1 ? "Finish" : "Continue";
        OnboardingChoicePicker.DisplayMemberPath = string.Empty;
        switch (step)
        {
            case OnboardingStep.Welcome:
                OnboardingTitleText.Text = "Where are you starting?";
                OnboardingBodyText.Text =
                    "Create a fresh Honor run or record an existing run without touching game files or saves.";
                OnboardingChoicePicker.ItemsSource = new[] { "Fresh run", "Already in progress" };
                OnboardingChoicePicker.SelectedIndex =
                    onboardingMode == OnboardingMode.Fresh ? 0 : 1;
                break;
            case OnboardingStep.Difficulty:
                OnboardingTitleText.Text = "Choose the run difficulty";
                OnboardingBodyText.Text =
                    "The overlay supports Balanced, Tactician, and Honour. Explorer is intentionally unsupported because it does not allow multiclassing.";
                OnboardingChoicePicker.ItemsSource =
                    RunDifficultyExtensions.SelectableOverlayDifficulties;
                OnboardingChoicePicker.SelectedItem = onboardingDifficulty;
                break;
            case OnboardingStep.Spoilers:
                OnboardingTitleText.Text = "Choose route visibility";
                OnboardingBodyText.Text =
                    "Show the complete reviewed route or reveal only the next three unresolved steps.";
                OnboardingChoicePicker.ItemsSource = Enum.GetValues<RouteRevealPolicy>();
                OnboardingChoicePicker.SelectedItem = onboardingReveal;
                break;
            case OnboardingStep.Ai:
                OnboardingTitleText.Text = "Local guide first";
                OnboardingBodyText.Text =
                    "The local guide works offline. Typed OpenRouter chat is optional and can be configured later in Settings.";
                OnboardingChoicePicker.ItemsSource = new[] { "Guide only", "Configure OpenRouter later" };
                OnboardingChoicePicker.SelectedIndex = 0;
                break;
            case OnboardingStep.Party:
                OnboardingTitleText.Text = "Review the default party";
                OnboardingBodyText.Text =
                    "Tav, Shadowheart, Lae'zel, and Astarion begin active. You can move companions, hirelings, and levels from Party at any time.";
                OnboardingChoicePicker.ItemsSource = new[] { "Use default party" };
                OnboardingChoicePicker.SelectedIndex = 0;
                break;
            case OnboardingStep.CatchUp:
                OnboardingTitleText.Text = "Mark existing progress";
                OnboardingBodyText.Text =
                    "Choose the last reviewed route landmark you have already reached. Earlier steps are recorded as caught up, not fabricated as completed.";
                OnboardingChoicePicker.DisplayMemberPath = "Title";
                OnboardingChoicePicker.ItemsSource =
                    controller.Walkthrough.Where(step => step.CheckpointId is not null).ToList();
                OnboardingChoicePicker.SelectedIndex = 0;
                break;
            case OnboardingStep.Ready:
                OnboardingTitleText.Text = "Ready";
                OnboardingBodyText.Text =
                    "The assistant runs as a normal user, stores run state locally, and only detects documented process/window names. Act 2 route content is unavailable in this guide version.";
                OnboardingChoicePicker.ItemsSource = new[] { "Finish setup" };
                OnboardingChoicePicker.SelectedIndex = 0;
                break;
        }
    }

    private void OnOnboardingBackClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        if (onboardingIndex > 0)
        {
            onboardingIndex--;
            ShowOnboardingStep();
        }
    }

    private async void OnOnboardingNextClick(object sender, RoutedEventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        var step = onboardingSteps[onboardingIndex];
        if (step == OnboardingStep.Welcome)
        {
            var nextMode = OnboardingChoicePicker.SelectedIndex == 1
                ? OnboardingMode.MidRun
                : OnboardingMode.Fresh;
            if (nextMode != onboardingMode)
            {
                onboardingMode = nextMode;
                onboardingSteps = OnboardingFlow.Steps(onboardingMode);
            }
        }
        else if (step == OnboardingStep.Difficulty &&
                 OnboardingChoicePicker.SelectedItem is RunDifficulty difficulty)
        {
            onboardingDifficulty = difficulty;
        }
        else if (step == OnboardingStep.Spoilers &&
                 OnboardingChoicePicker.SelectedItem is RouteRevealPolicy reveal)
        {
            onboardingReveal = reveal;
        }
        else if (step == OnboardingStep.CatchUp &&
                 OnboardingChoicePicker.SelectedItem is WalkthroughStep landmark &&
                 landmark.CheckpointId is { } checkpointId)
        {
            controller.Run.WalkthroughProgress = CatchUp.Ledger(
                    checkpointId,
                    controller.Walkthrough,
                    controller.Run.WalkthroughProgress ?? new())
                ?.ToDictionary(pair => pair.Key, pair => pair.Value);
        }

        if (onboardingIndex < onboardingSteps.Count - 1)
        {
            onboardingIndex++;
            ShowOnboardingStep();
            return;
        }

        controller.Run.Difficulty = onboardingDifficulty;
        controller.Run.RouteRevealPolicy = onboardingReveal;
        await controller.SaveAsync();
        await controller.UpdatePreferencesAsync(
            controller.Preferences with
            {
                OnboardingVersion = OnboardingFlow.Version,
            });
        OnboardingPanel.Visibility = Visibility.Collapsed;
        RefreshView();
    }

    protected override void OnClosed(EventArgs eventArgs)
    {
        controller.StateChanged -= OnControllerStateChanged;
        overlay.StateChanged -= OnOverlayStateChanged;
        overlay.OpenRouteRequested -= OnOverlayOpenRouteRequested;
        overlay.OpenChatRequested -= OnOverlayOpenChatRequested;
        overlay.TaskDoneRequested -= OnOverlayTaskDoneRequested;
        overlay.SnoozeRequested -= OnOverlaySnoozeRequested;
        overlay.MuteRequested -= OnOverlayMuteRequested;
        overlay.PinRequested -= OnOverlayPinRequested;
        chatCancellation?.Cancel();
        importCancellation?.Cancel();
        keyTestCancellation?.Cancel();
        chatLines.Clear();
        base.OnClosed(eventArgs);
    }

    private void ShowError(string message)
    {
        MessageBox.Show(
            this,
            message,
            "BG3 Honor Assistant",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }

    private sealed record ChatLineRow(
        string Role,
        string Text,
        IReadOnlyList<ChatSource> Sources,
        bool IsError);

    private sealed record ActGearRow(BuildGear Gear, string Status)
    {
        public string Item => $"{Gear.Item} — {Status}";
    }
}
