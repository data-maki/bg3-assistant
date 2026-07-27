using System.ComponentModel;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Navigation;
using BG3HonorAssistant.App.UI;
using BG3HonorAssistant.Core.Chat;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Overlay;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Infrastructure.BuildImport;
using BG3HonorAssistant.Infrastructure.Networking;
using BG3HonorAssistant.Infrastructure.OpenRouter;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Windows.Credentials;
using BG3HonorAssistant.Windows.Packaging;
using BG3HonorAssistant.Windows.Shell;
using BG3HonorAssistant.Windows.Startup;
using Application = System.Windows.Application;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;

namespace BG3HonorAssistant.App;

public partial class MainWindow
{
    private async Task<bool> ImportBuildFromUrlAsync(
        string rawUrl,
        string? assignMemberId,
        Action<string> setStatus)
    {
        if (importCancellation is not null)
        {
            return false;
        }

        if (rawUrl.Length == 0)
        {
            setStatus("Enter a public HTTPS build URL.");
            return false;
        }

        string? apiKey;
        try
        {
            apiKey = credentialStore.Read();
        }
        catch (Exception exception)
        {
            setStatus(
                $"Windows Credential Manager could not read the OpenRouter key: {exception.Message}");
            return false;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            openRouterKeyConfigured = false;
            setStatus("Save an OpenRouter key in Settings before importing a build.");
            UpdateNetworkButtons();
            return false;
        }

        var cancellation = new CancellationTokenSource();
        importCancellation = cancellation;
        var operationVersion = ++importOperationVersion;
        setStatus(
            "Downloading and validating the public source, then asking the pinned model…");
        UpdateNetworkButtons();
        try
        {
            var imported = await buildImporter.ImportAsync(
                rawUrl,
                apiKey,
                cancellation.Token);
            if (operationVersion != importOperationVersion)
            {
                return false;
            }

            await controller.SaveImportedBuildAsync(
                imported,
                cancellation.Token);
            var importedBuild = controller.Builds.FirstOrDefault(
                build => build.Id == imported.Id);
            var status =
                $"Imported “{imported.Name}”. Verify every choice in game before relying on it.";
            if (assignMemberId is { } memberId &&
                importedBuild is not null &&
                (controller.Run.Roster ?? controller.Run.Party).FirstOrDefault(
                    member => member.Id == memberId) is { } member)
            {
                if (member.BuildId is null)
                {
                    await controller.AssignBuildAsync(
                        member.Id,
                        importedBuild.Id,
                        cancellation.Token);
                    status += $" Assigned to {member.Name}.";
                }
                else
                {
                    var assignmentStatus =
                        $"{status} Assigned to {member.Name}.";
                    ShowActionConfirmation(
                        $"Assign “{importedBuild.Name}” to {member.Name}?",
                        "Replacing this build clears run-specific equipment and temporary setup choices. Permanent rewards stay.",
                        "Assign imported build",
                        async () =>
                        {
                            await controller.AssignBuildAsync(
                                member.Id,
                                importedBuild.Id);
                            setStatus(assignmentStatus);
                        });
                    status += $" Confirm assignment to {member.Name}.";
                }
            }

            setStatus(status);
            return true;
        }
        catch (OperationCanceledException)
        {
            if (operationVersion == importOperationVersion)
            {
                setStatus("Build import cancelled.");
            }
        }
        catch (Exception exception) when (
            exception is
                PublicNetworkException or
                BuildImportSourceException or
                OpenRouterException or
                BuildImportProcessingException)
        {
            if (operationVersion == importOperationVersion)
            {
                setStatus($"Build import failed: {exception.Message}");
            }
        }
        finally
        {
            cancellation.Dispose();
            if (ReferenceEquals(importCancellation, cancellation))
            {
                importCancellation = null;
            }

            UpdateNetworkButtons();
        }

        return false;
    }
}
