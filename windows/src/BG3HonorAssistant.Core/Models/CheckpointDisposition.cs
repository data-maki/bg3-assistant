namespace BG3HonorAssistant.Core.Models;

public enum CheckpointDisposition
{
    Pending,
    Completed,
    Skipped,
    CaughtUp,
}

public static class CheckpointDispositionExtensions
{
    public static bool CountsAsCompleted(this CheckpointDisposition disposition)
    {
        return disposition is CheckpointDisposition.Completed or CheckpointDisposition.CaughtUp;
    }
}
