using BG3HonorAssistant.Windows.Credentials;

namespace BG3HonorAssistant.Windows.Tests.Credentials;

public sealed class CredentialStoreTests
{
    [Fact]
    public void RoundTripsAndDeletesCurrentUserCredential()
    {
        var target = $"BG3HonorAssistant.Tests/{Guid.NewGuid():N}";
        var store = new CredentialStore(target);

        try
        {
            Assert.Null(store.Read());
            store.Save("disposable-test-secret");
            Assert.Equal("disposable-test-secret", store.Read());
            store.Save("  replacement-secret  ");
            Assert.Equal("replacement-secret", store.Read());
            Assert.True(store.Delete());
            Assert.Null(store.Read());
            Assert.False(store.Delete());
        }
        finally
        {
            _ = store.Delete();
        }
    }

    [Fact]
    public void RejectsEmptySecret()
    {
        var store = new CredentialStore($"BG3HonorAssistant.Tests/{Guid.NewGuid():N}");

        Assert.Throws<ArgumentException>(() => store.Save(string.Empty));
    }
}
