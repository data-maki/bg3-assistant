using System.Globalization;
using System.IO;
using System.Windows.Data;
using System.Windows.Media.Imaging;
using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.App.UI;

internal static class AssetImage
{
    private static readonly Dictionary<string, BitmapImage?> Cache =
        new(StringComparer.OrdinalIgnoreCase);

    public static BitmapImage? Load(params string[] path)
    {
        var fullPath = Path.Combine(
            [AppContext.BaseDirectory, "Resources", .. path]);
        if (Cache.TryGetValue(fullPath, out var cached))
        {
            return cached;
        }

        if (!File.Exists(fullPath))
        {
            Cache[fullPath] = null;
            return null;
        }

        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(fullPath, UriKind.Absolute);
        image.EndInit();
        image.Freeze();
        Cache[fullPath] = image;
        return image;
    }
}

internal sealed class CompanionPortraitConverter : IValueConverter
{
    private static readonly IReadOnlyDictionary<string, string> Filenames =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Shadowheart"] = "shadowheart.png",
            ["Lae'zel"] = "laezel.png",
            ["Astarion"] = "astarion.png",
            ["Gale"] = "gale.png",
            ["Wyll"] = "wyll.png",
            ["Karlach"] = "karlach.png",
            ["Dark Urge"] = "dark-urge.png",
            ["Halsin"] = "halsin.png",
            ["Minthara"] = "minthara.png",
            ["Jaheira"] = "jaheira.png",
            ["Minsc"] = "minsc.png",
        };

    public object? Convert(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture)
    {
        _ = targetType;
        _ = parameter;
        _ = culture;
        return value is string name && Filenames.TryGetValue(name, out var filename)
            ? AssetImage.Load("CompanionPortraits", filename)
            : null;
    }

    public object ConvertBack(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture) =>
        throw new NotSupportedException();
}

internal sealed class ItemIconConverter : IValueConverter
{
    public object? Convert(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture)
    {
        _ = targetType;
        _ = parameter;
        _ = culture;
        var path = value switch
        {
            string raw => raw,
            BuildGear gear => gear.Icon,
            _ => null,
        };
        var filename = string.IsNullOrWhiteSpace(path)
            ? null
            : Path.GetFileName(path);
        return string.IsNullOrWhiteSpace(filename)
            ? null
            : AssetImage.Load("ItemIcons", filename);
    }

    public object ConvertBack(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture) =>
        throw new NotSupportedException();
}

internal sealed class BuildOptionIconConverter : IValueConverter
{
    public object? Convert(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture)
    {
        _ = targetType;
        _ = parameter;
        _ = culture;
        return value is string name
            ? AssetImage.Load(
                "BuildOptionIcons",
                BuildArtwork.Slug(name) + ".webp")
            : null;
    }

    public object ConvertBack(
        object value,
        Type targetType,
        object parameter,
        CultureInfo culture) =>
        throw new NotSupportedException();
}
