using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class ActLedgerTests
{
    [Fact]
    public void OnlyPastActLedgersAreLocked()
    {
        var run = new HonorRun { SelectedAct = 2 };

        Assert.True(run.ActLedgerIsLocked(1));
        Assert.False(run.ActLedgerIsLocked(2));
        Assert.False(run.ActLedgerIsLocked(3));
    }

    [Fact]
    public void FinalActRecordLocksActThreeLedger()
    {
        var run = new HonorRun
        {
            SelectedAct = 3,
            FinalActRecord = new ActTransitionRecord(
                3,
                3,
                new Dictionary<string, ActGearReviewStatus>
                {
                    ["item"] = ActGearReviewStatus.Obtained,
                },
                0,
                DateTimeOffset.FromUnixTimeSeconds(1)),
        };

        Assert.True(run.ActLedgerIsLocked(3));
        Assert.Equal(
            ActGearReviewStatus.Obtained,
            run.LockedActGearReviewStatus("item", 3));
    }
}
