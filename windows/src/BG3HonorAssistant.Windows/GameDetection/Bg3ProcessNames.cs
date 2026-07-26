namespace BG3HonorAssistant.Windows.GameDetection;

public static class Bg3ProcessNames
{
    public const string Vulkan = "bg3";
    public const string DirectX11 = "bg3_dx11";

    public static IReadOnlyList<string> All { get; } = [Vulkan, DirectX11];

    public static bool IsSupported(string? processName)
    {
        return All.Any(candidate =>
            string.Equals(candidate, processName, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                $"{candidate}.exe",
                processName,
                StringComparison.OrdinalIgnoreCase));
    }
}
