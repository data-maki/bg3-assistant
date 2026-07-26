namespace BG3HonorAssistant.Core.Models;

public enum RunDifficulty
{
    Explorer,
    Balanced,
    Tactician,
    Honour,
    Custom,
}

public static class RunDifficultyExtensions
{
    public static IReadOnlyList<RunDifficulty> SelectableOverlayDifficulties { get; } =
        [RunDifficulty.Balanced, RunDifficulty.Tactician, RunDifficulty.Honour];

    public static bool SupportsOverlay(this RunDifficulty difficulty) =>
        difficulty is not RunDifficulty.Explorer;
}

public enum RouteRevealPolicy
{
    Everything,
    NextThree,
}

public enum OnboardingMode
{
    Fresh,
    MidRun,
}

public enum OnboardingStep
{
    Welcome,
    Difficulty,
    Spoilers,
    Ai,
    Party,
    CatchUp,
    Ready,
}

public static class OnboardingFlow
{
    public const int Version = 5;

    public static IReadOnlyList<OnboardingStep> Steps(OnboardingMode mode) =>
        mode == OnboardingMode.MidRun
            ? [
                OnboardingStep.Welcome,
                OnboardingStep.Difficulty,
                OnboardingStep.Spoilers,
                OnboardingStep.Ai,
                OnboardingStep.Party,
                OnboardingStep.CatchUp,
                OnboardingStep.Ready,
            ]
            : [
                OnboardingStep.Welcome,
                OnboardingStep.Difficulty,
                OnboardingStep.Spoilers,
                OnboardingStep.Ai,
                OnboardingStep.Party,
                OnboardingStep.Ready,
            ];

    public static bool AllowsAdvance(
        OnboardingStep step,
        RunDifficulty difficulty) =>
        step != OnboardingStep.Difficulty || difficulty.SupportsOverlay();
}

public static class WindowsMvpCapabilities
{
    public const bool SupportsLocalAi = false;
    public const bool SupportsImageMessages = false;
    public const bool SupportsScreenshotCapture = false;
    public const bool SupportsMicrophoneOrSpeech = false;
}

public static class CatchUp
{
    public static IReadOnlyDictionary<string, CheckpointDisposition>? Ledger(
        string markingThroughCheckpointId,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition> existing)
    {
        var landmark = walkthrough.FirstOrDefault(
            step => step.CheckpointId == markingThroughCheckpointId);
        if (landmark is null)
        {
            return null;
        }

        var ledger = new Dictionary<string, CheckpointDisposition>(
            existing,
            StringComparer.Ordinal);
        foreach (var step in walkthrough.Where(step => step.Order <= landmark.Order))
        {
            ledger.TryAdd(step.Id, CheckpointDisposition.CaughtUp);
        }

        return ledger;
    }
}
