using System.Diagnostics;
using System.IO;

namespace BG3HonorAssistant.Windows.Shell;

public sealed class GameLauncher
{
    public const string SteamUri = "steam://run/1086940";

    public void LaunchSteamEdition()
    {
        Process.Start(new ProcessStartInfo(SteamUri)
        {
            UseShellExecute = true,
        });
    }

    public void OpenExternalMap(string value)
    {
        if (!TryCreateHttpUri(value, out var uri))
        {
            throw new ArgumentException(
                "The map link must be an absolute HTTP or HTTPS URL.",
                nameof(value));
        }

        Process.Start(new ProcessStartInfo(uri.AbsoluteUri)
        {
            UseShellExecute = true,
        });
    }

    public void OpenSupportEmail()
    {
        Process.Start(new ProcessStartInfo(
            "mailto:jcllobet@gmail.com?subject=BG3%20Overlay%20bug%20report")
        {
            UseShellExecute = true,
        });
    }

    public void OpenLocalFile(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("The bundled file was not found.", path);
        }

        Process.Start(new ProcessStartInfo(path)
        {
            UseShellExecute = true,
        });
    }

    public static bool TryCreateHttpUri(string value, out Uri uri)
    {
        if (Uri.TryCreate(value, UriKind.Absolute, out var candidate) &&
            candidate.Scheme is "http" or "https")
        {
            uri = candidate;
            return true;
        }

        uri = null!;
        return false;
    }
}
