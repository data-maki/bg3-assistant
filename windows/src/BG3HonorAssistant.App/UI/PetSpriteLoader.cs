using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BG3HonorAssistant.Core.Overlay;

namespace BG3HonorAssistant.App;

public static class PetSpriteLoader
{
    private const int CellWidth = 192;
    private const int CellHeight = 208;
    private static readonly Lazy<BitmapSource?> Sheet = new(LoadSheet);
    private static readonly Dictionary<PetSpriteFrame, BitmapSource?> Frames = [];
    private static readonly object Sync = new();

    public static BitmapSource? Frame(PetSpriteFrame frame)
    {
        if (frame is { Row: < 0 or > 10 } ||
            frame is { Column: < 0 or > 7 })
        {
            return null;
        }

        lock (Sync)
        {
            if (Frames.TryGetValue(frame, out var cached))
            {
                return cached;
            }

            var sheet = Sheet.Value;
            if (sheet is null)
            {
                Frames[frame] = null;
                return null;
            }

            var y = sheet.PixelHeight - ((frame.Row + 1) * CellHeight);
            if (y < 0 ||
                ((frame.Column + 1) * CellWidth) > sheet.PixelWidth)
            {
                Frames[frame] = null;
                return null;
            }

            var cropped = new CroppedBitmap(
                sheet,
                new Int32Rect(
                    frame.Column * CellWidth,
                    y,
                    CellWidth,
                    CellHeight));
            cropped.Freeze();
            Frames[frame] = cropped;
            return cropped;
        }
    }

    private static BitmapSource? LoadSheet()
    {
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "Resources",
            "twilight-cleric.png");
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new System.Uri(path);
            bitmap.EndInit();
            bitmap.Freeze();
            return bitmap.PixelWidth == 1536 && bitmap.PixelHeight == 2288
                ? bitmap
                : null;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
