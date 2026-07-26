using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    public async Task SaveImportedBuildAsync(
        ImportedBuild imported,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(imported);
        await runRepository.SaveImportedBuildAsync(
            imported.Id,
            imported.Name,
            JsonSerializer.Serialize(imported, json),
            cancellationToken);
        await RefreshImportedBuildsAsync(cancellationToken);
        Notify();
    }

    public async Task<bool> DeleteImportedBuildAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        if (Run.Party.Any(member => member.BuildId == id))
        {
            return false;
        }

        var deleted = await runRepository.DeleteImportedBuildAsync(id, cancellationToken);
        if (deleted)
        {
            await RefreshImportedBuildsAsync(cancellationToken);
            Notify();
        }

        return deleted;
    }
}
