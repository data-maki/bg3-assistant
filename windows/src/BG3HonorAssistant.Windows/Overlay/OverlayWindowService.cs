using System.ComponentModel;
using BG3HonorAssistant.Windows.GameDetection;
using BG3HonorAssistant.Windows.Interop;

namespace BG3HonorAssistant.Windows.Overlay;

public sealed class OverlayWindowService
{
    public void Configure(nint overlayWindow, bool passive)
    {
        ArgumentOutOfRangeException.ThrowIfZero(overlayWindow);

        var styles = NativeMethods.GetWindowLongPtr(overlayWindow, NativeMethods.GwlExStyle).ToInt64();
        // WS_EX_TOPMOST is z-order state owned by SetWindowPos. Writing that
        // bit directly can make Windows treat the following HWND_TOPMOST call
        // as a no-op while the HWND is still in the non-topmost band.
        styles = (styles | NativeMethods.WsExToolWindow) & ~NativeMethods.WsExTopmost;
        styles = passive
            ? styles | NativeMethods.WsExNoActivate
            : styles & ~NativeMethods.WsExNoActivate;

        NativeMethods.SetWindowLongPtr(
            overlayWindow,
            NativeMethods.GwlExStyle,
            new nint(styles));

        if (!NativeMethods.SetWindowPos(
                overlayWindow,
                NativeMethods.HwndTopmost,
                0,
                0,
                0,
                0,
                NativeMethods.SwpNoMove |
                NativeMethods.SwpNoSize |
                NativeMethods.SwpNoActivate))
        {
            throw new Win32Exception();
        }
    }

    public void SetPassive(nint overlayWindow, bool passive)
    {
        Configure(overlayWindow, passive);
    }

    public void PositionRelativeTo(
        nint overlayWindow,
        Bg3WindowInfo game,
        double widthInDeviceIndependentPixels,
        double heightInDeviceIndependentPixels)
    {
        var placement = OverlayPlacementCalculator.AtRightEdge(
            game.Bounds,
            OverlayDpiCalculator.ToPhysicalPixels(
                widthInDeviceIndependentPixels,
                game.Dpi),
            OverlayDpiCalculator.ToPhysicalPixels(
                heightInDeviceIndependentPixels,
                game.Dpi));

        if (!NativeMethods.SetWindowPos(
                overlayWindow,
                NativeMethods.HwndTopmost,
                placement.X,
                placement.Y,
                placement.Width,
                placement.Height,
                NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow))
        {
            throw new Win32Exception();
        }
    }

    public void PositionAtRightEdge(nint overlayWindow, Bg3WindowInfo game)
    {
        PositionAtAnchor(overlayWindow, game, anchor: null);
    }

    public void PositionAtAnchor(
        nint overlayWindow,
        Bg3WindowInfo game,
        OverlayAnchor? anchor)
    {
        ArgumentOutOfRangeException.ThrowIfZero(overlayWindow);
        if (!NativeMethods.GetWindowRect(overlayWindow, out var overlayRect))
        {
            throw new Win32Exception();
        }

        var overlayWidth = overlayRect.Right - overlayRect.Left;
        var overlayHeight = overlayRect.Bottom - overlayRect.Top;
        var placement = anchor is { } saved
            ? OverlayPlacementCalculator.AtNormalizedAnchor(
                game.Bounds,
                overlayWidth,
                overlayHeight,
                saved)
            : OverlayPlacementCalculator.AtRightEdge(
                game.Bounds,
                overlayWidth,
                overlayHeight);
        if (!NativeMethods.SetWindowPos(
                overlayWindow,
                NativeMethods.HwndTopmost,
                placement.X,
                placement.Y,
                0,
                0,
                NativeMethods.SwpNoSize |
                NativeMethods.SwpNoActivate |
                NativeMethods.SwpShowWindow))
        {
            throw new Win32Exception();
        }
    }

    public OverlayAnchor ReadNormalizedAnchor(
        nint overlayWindow,
        Bg3WindowInfo game)
    {
        ArgumentOutOfRangeException.ThrowIfZero(overlayWindow);
        if (!NativeMethods.GetWindowRect(overlayWindow, out var overlayRect))
        {
            throw new Win32Exception();
        }

        return OverlayPlacementCalculator.Normalize(
            game.Bounds,
            new OverlayPlacement(
                overlayRect.Left,
                overlayRect.Top,
                overlayRect.Right - overlayRect.Left,
                overlayRect.Bottom - overlayRect.Top));
    }

    public static void EnablePerMonitorV2DpiAwareness()
    {
        _ = NativeMethods.SetProcessDpiAwarenessContext(
            NativeMethods.DpiAwarenessContextPerMonitorAwareV2);
    }
}
