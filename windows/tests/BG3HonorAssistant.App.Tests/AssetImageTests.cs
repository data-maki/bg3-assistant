using System.IO;
using System.Linq;
using System.Windows.Media.Imaging;
using BG3HonorAssistant.App.UI;

namespace BG3HonorAssistant.App.Tests;

public sealed class AssetImageTests
{
    [Fact]
    public void EveryPackagedArtworkDerivativeIsWpfDecodable()
    {
        var inventories = new[]
        {
            (Directory: "BuildOptionIcons", Expected: 695),
            (Directory: "ItemIcons", Expected: 51),
        };

        foreach (var inventory in inventories)
        {
            var root = Path.Combine(
                AppContext.BaseDirectory,
                "Resources",
                inventory.Directory);
            var files = Directory
                .EnumerateFiles(root, "*.png", SearchOption.TopDirectoryOnly)
                .Order(StringComparer.Ordinal)
                .ToList();

            Assert.Equal(inventory.Expected, files.Count);
            Assert.All(
                files,
                path =>
                    Assert.IsType<BitmapImage>(
                        AssetImage.Load(
                            inventory.Directory,
                            Path.GetFileName(path))));
        }
    }

    [Fact]
    public void PackagedBuildArtworkUsesWpfDecodablePng()
    {
        var converter = new BuildOptionIconConverter();

        var result = converter.Convert(
            "Bard",
            typeof(BitmapImage),
            parameter: null!,
            culture: System.Globalization.CultureInfo.InvariantCulture);

        var image = Assert.IsType<BitmapImage>(result);
        Assert.EndsWith(
            "Resources/BuildOptionIcons/bard.png",
            image.UriSource.AbsoluteUri,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void EmptyOptionalArtworkDoesNotCrashThePlayerFlow()
    {
        var converter = new BuildOptionIconConverter();

        var result = converter.Convert(
            "Friends",
            typeof(BitmapImage),
            parameter: null!,
            culture: System.Globalization.CultureInfo.InvariantCulture);

        Assert.Null(result);
    }
}
