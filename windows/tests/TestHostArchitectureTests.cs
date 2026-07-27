using System.Runtime.InteropServices;

namespace BG3HonorAssistant.Tests;

public sealed class TestHostArchitectureTests
{
    [Fact]
    public void TestHostUsesTheExplicitBuildArchitecture()
    {
#if BG3_TESTHOST_ARM64
        const Architecture expected = Architecture.Arm64;
#elif BG3_TESTHOST_X64
        const Architecture expected = Architecture.X64;
#else
#error The explicit BG3 testhost architecture constant is missing.
#endif

        Assert.Equal(expected, RuntimeInformation.ProcessArchitecture);
        Assert.Equal(8, nint.Size);
    }
}
