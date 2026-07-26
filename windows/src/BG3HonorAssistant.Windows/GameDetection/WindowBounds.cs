namespace BG3HonorAssistant.Windows.GameDetection;

public readonly record struct WindowBounds(int Left, int Top, int Right, int Bottom)
{
    public int Width => Math.Max(0, Right - Left);

    public int Height => Math.Max(0, Bottom - Top);

    public bool IsUsable => Width > 0 && Height > 0;
}
