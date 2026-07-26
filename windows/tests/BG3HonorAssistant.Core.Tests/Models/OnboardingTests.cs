using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class OnboardingTests
{
    [Fact]
    public void ProviderSetupStepIsPresentForBothOnboardingPaths()
    {
        Assert.Equal(
            [
                OnboardingStep.Welcome,
                OnboardingStep.Difficulty,
                OnboardingStep.Spoilers,
                OnboardingStep.Ai,
                OnboardingStep.Party,
                OnboardingStep.Ready,
            ],
            OnboardingFlow.Steps(OnboardingMode.Fresh));
        Assert.Equal(
            [
                OnboardingStep.Welcome,
                OnboardingStep.Difficulty,
                OnboardingStep.Spoilers,
                OnboardingStep.Ai,
                OnboardingStep.Party,
                OnboardingStep.CatchUp,
                OnboardingStep.Ready,
            ],
            OnboardingFlow.Steps(OnboardingMode.MidRun));
    }

    [Fact]
    public void OnlyKnownOverlayDifficultiesAreSelectable()
    {
        Assert.Equal(
            [
                RunDifficulty.Balanced,
                RunDifficulty.Tactician,
                RunDifficulty.Honour,
            ],
            RunDifficultyExtensions.SelectableOverlayDifficulties);
        Assert.False(RunDifficulty.Explorer.SupportsOverlay());
        Assert.True(RunDifficulty.Custom.SupportsOverlay());
        Assert.False(
            OnboardingFlow.AllowsAdvance(
                OnboardingStep.Difficulty,
                RunDifficulty.Explorer));
        Assert.True(
            OnboardingFlow.AllowsAdvance(
                OnboardingStep.Difficulty,
                RunDifficulty.Balanced));
        Assert.True(
            OnboardingFlow.AllowsAdvance(
                OnboardingStep.Spoilers,
                RunDifficulty.Explorer));
    }

    [Fact]
    public void WindowsMvpExplicitlyExcludesLocalModels()
    {
        Assert.False(WindowsMvpCapabilities.SupportsLocalAi);
    }

    [Fact]
    public void WindowsMvpExplicitlyExcludesImageMessages()
    {
        Assert.False(WindowsMvpCapabilities.SupportsImageMessages);
        Assert.False(WindowsMvpCapabilities.SupportsScreenshotCapture);
        Assert.False(WindowsMvpCapabilities.SupportsMicrophoneOrSpeech);
    }

    [Fact]
    public void CatchUpMarksThroughLandmarkInclusive()
    {
        var walkthrough = new[]
        {
            Step("s1", 1, "cp1"),
            Step("s2", 2),
            Step("s3", 3, "cp2"),
            Step("s4", 4),
        };

        var ledger = CatchUp.Ledger(
            "cp2",
            walkthrough,
            new Dictionary<string, CheckpointDisposition>());

        Assert.NotNull(ledger);
        Assert.Equal(CheckpointDisposition.CaughtUp, ledger["s1"]);
        Assert.Equal(CheckpointDisposition.CaughtUp, ledger["s2"]);
        Assert.Equal(CheckpointDisposition.CaughtUp, ledger["s3"]);
        Assert.False(ledger.ContainsKey("s4"));
    }

    [Fact]
    public void CatchUpPreservesExplicitHistory()
    {
        var walkthrough = new[]
        {
            Step("s1", 1, "cp1"),
            Step("s2", 2, "cp2"),
        };

        var ledger = CatchUp.Ledger(
            "cp2",
            walkthrough,
            new Dictionary<string, CheckpointDisposition>
            {
                ["s1"] = CheckpointDisposition.Skipped,
            });

        Assert.NotNull(ledger);
        Assert.Equal(CheckpointDisposition.Skipped, ledger["s1"]);
        Assert.Equal(CheckpointDisposition.CaughtUp, ledger["s2"]);
    }

    private static WalkthroughStep Step(
        string id,
        int order,
        string? checkpointId = null) =>
        new()
        {
            Id = id,
            Order = order,
            Phase = "Phase",
            PhaseOrder = 1,
            Title = $"Title {id}",
            Kind = "exploration",
            Importance = "core",
            Region = "Wilderness",
            Area = "Area",
            MinimumLevel = 1,
            CheckpointId = checkpointId,
        };
}
