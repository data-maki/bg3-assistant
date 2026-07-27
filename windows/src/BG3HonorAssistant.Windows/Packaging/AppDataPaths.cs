using System.IO;

namespace BG3HonorAssistant.Windows.Packaging;

public sealed record AppDataPaths(string Root)
{
    public const string StateDirectoryEnvironmentVariable =
        "BG3_HONOR_ASSISTANT_STATE_DIR";
    public const string QaDirectoryName = "QA";

    public string Database => Path.Combine(Root, "assistant.sqlite3");

    public string Logs => Path.Combine(Root, "Logs");

    public static AppDataPaths Current()
    {
        var local = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);
        var family = PackageIdentity.TryGetFamilyName();
        return Resolve(
            local,
            family,
            Environment.GetEnvironmentVariable(StateDirectoryEnvironmentVariable));
    }

    public static AppDataPaths Resolve(
        string localApplicationData,
        string? packageFamilyName,
        string? stateDirectoryOverride = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(localApplicationData);
        if (!string.IsNullOrWhiteSpace(stateDirectoryOverride))
        {
            if (!Path.IsPathFullyQualified(stateDirectoryOverride))
            {
                throw new InvalidOperationException(
                    $"{StateDirectoryEnvironmentVariable} must be an absolute path.");
            }

            var candidate = Path.GetFullPath(stateDirectoryOverride);
            var candidateRoot = Path.GetPathRoot(candidate);
            if (candidate.StartsWith(@"\\", StringComparison.Ordinal) ||
                string.IsNullOrEmpty(candidateRoot) ||
                string.Equals(
                    Path.TrimEndingDirectorySeparator(candidate),
                    Path.TrimEndingDirectorySeparator(candidateRoot),
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    $"{StateDirectoryEnvironmentVariable} must not use a drive, UNC, or device root.");
            }

            var localQaRoot = Path.Combine(
                Path.GetFullPath(localApplicationData),
                "BG3HonorAssistant",
                QaDirectoryName);
            var temporaryQaRoot = Path.Combine(
                Path.GetFullPath(Path.GetTempPath()),
                "BG3HonorAssistant.QA");
            if (!IsStrictDescendant(candidate, localQaRoot) &&
                !IsStrictDescendant(candidate, temporaryQaRoot))
            {
                throw new InvalidOperationException(
                    $"{StateDirectoryEnvironmentVariable} must be a dedicated child of " +
                    $"{localQaRoot} or {temporaryQaRoot}.");
            }

            return new AppDataPaths(candidate);
        }

        var local = Path.GetFullPath(localApplicationData);
        var root = string.IsNullOrWhiteSpace(packageFamilyName)
            ? Path.Combine(local, "BG3HonorAssistant")
            : Path.Combine(local, "Packages", packageFamilyName, "LocalState");
        return new AppDataPaths(root);
    }

    private static bool IsStrictDescendant(string candidate, string root)
    {
        var relative = Path.GetRelativePath(root, candidate);
        return !string.Equals(relative, ".", StringComparison.Ordinal) &&
               !string.Equals(relative, "..", StringComparison.Ordinal) &&
               !relative.StartsWith(
                   $"..{Path.DirectorySeparatorChar}",
                   StringComparison.Ordinal) &&
               !Path.IsPathRooted(relative);
    }
}
