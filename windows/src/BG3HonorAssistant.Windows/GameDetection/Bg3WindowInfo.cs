namespace BG3HonorAssistant.Windows.GameDetection;

public sealed record Bg3WindowInfo(
    int ProcessId,
    string ProcessName,
    nint WindowHandle,
    WindowBounds Bounds,
    uint Dpi);
