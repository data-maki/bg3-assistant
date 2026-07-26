using System.IO;

namespace BG3HonorAssistant.Windows.Packaging;

public sealed record AppDataPaths(string Root)
{
    public string Database => Path.Combine(Root, "assistant.sqlite3");

    public string Logs => Path.Combine(Root, "Logs");

    public static AppDataPaths Current()
    {
        var local = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);
        var family = PackageIdentity.TryGetFamilyName();
        var root = family is null
            ? Path.Combine(local, "BG3HonorAssistant")
            : Path.Combine(local, "Packages", family, "LocalState");
        return new AppDataPaths(root);
    }
}
