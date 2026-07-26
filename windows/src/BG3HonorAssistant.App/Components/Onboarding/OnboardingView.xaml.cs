using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BG3HonorAssistant.App.Components.Onboarding;

public partial class OnboardingView : UserControl
{
    private MainWindow Host { get; set; } = null!;

    public OnboardingView()
    {
        InitializeComponent();
    }

    internal void Attach(MainWindow host)
    {
        Host = host;
    }

    private void OnCloseExplorerOverlayClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnCloseExplorerOverlayClick(sender, eventArgs);

    private void OnOnboardingActClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingActClick(sender, eventArgs);

    private void OnOnboardingAiChoiceClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingAiChoiceClick(sender, eventArgs);

    private void OnOnboardingBackClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingBackClick(sender, eventArgs);

    private void OnOnboardingDifficultyClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingDifficultyClick(sender, eventArgs);

    private void OnOnboardingLandmarkChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnOnboardingLandmarkChanged(sender, eventArgs);

    private void OnOnboardingLevelDownClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingLevelDownClick(sender, eventArgs);

    private void OnOnboardingLevelUpClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingLevelUpClick(sender, eventArgs);

    private void OnOnboardingModeClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingModeClick(sender, eventArgs);

    private void OnOnboardingNextClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingNextClick(sender, eventArgs);

    private void OnOnboardingRosterStatusChanged(object sender, SelectionChangedEventArgs eventArgs) =>
        Host.OnOnboardingRosterStatusChanged(sender, eventArgs);

    private void OnOnboardingSpoilerClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnOnboardingSpoilerClick(sender, eventArgs);

    private void OnSaveOnboardingKeyClick(object sender, RoutedEventArgs eventArgs) =>
        Host.OnSaveOnboardingKeyClick(sender, eventArgs);
}
