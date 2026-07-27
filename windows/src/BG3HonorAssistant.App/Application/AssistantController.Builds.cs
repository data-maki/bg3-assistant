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
        var value = JsonSerializer.Serialize(imported, json);
        await EnqueuePersistenceAsync(
            async token =>
            {
                await runRepository.SaveImportedBuildAsync(
                    imported.Id,
                    imported.Name,
                    value,
                    token).ConfigureAwait(false);
                await RefreshImportedBuildsAsync(token).ConfigureAwait(false);
            },
            cancellationToken);
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

        var deleted = await EnqueuePersistenceAsync(
            async token =>
            {
                var result = await runRepository.DeleteImportedBuildAsync(
                    id,
                    token).ConfigureAwait(false);
                if (result)
                {
                    await RefreshImportedBuildsAsync(token).ConfigureAwait(false);
                }

                return result;
            },
            cancellationToken);
        if (deleted)
        {
            Notify();
        }

        return deleted;
    }
}
