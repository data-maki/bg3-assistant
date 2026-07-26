using BG3HonorAssistant.Windows.SingleInstance;

namespace BG3HonorAssistant.Windows.Tests.SingleInstance;

public sealed class SingleInstanceServiceTests
{
    [Fact]
    public void AllowsOnlyOnePrimaryForApplicationId()
    {
        var applicationId = $"BG3HonorAssistant.Tests.{Guid.NewGuid():N}";
        using var first = new SingleInstanceService(applicationId);
        using var second = new SingleInstanceService(applicationId);

        Assert.True(first.IsPrimary);
        Assert.False(second.IsPrimary);
        Assert.Equal(first.ActivationMessage, second.ActivationMessage);
        Assert.True(second.NotifyExistingInstance());
    }

    [Fact]
    public void RejectsIdentifierWithoutSafeCharacters()
    {
        Assert.Throws<ArgumentException>(() => new SingleInstanceService("***"));
    }
}
