using System.Text.Json;
using BG3HonorAssistant.Core.Models;
using BG3HonorAssistant.Core.Route;
using BG3HonorAssistant.Core.Serialization;
using BG3HonorAssistant.Infrastructure.Persistence;
using BG3HonorAssistant.Infrastructure.Resources;

namespace BG3HonorAssistant.App;

public sealed partial class AssistantController
{
    public async Task<bool> SetActGearReviewAsync(
        BuildGear gear,
        ActGearReviewStatus status,
        CancellationToken cancellationToken = default)
    {
        return await SetActGearReviewAsync(
            gear,
            Run.SelectedAct ?? 1,
            status,
            cancellationToken);
    }

    public async Task<bool> SetActGearReviewAsync(
        BuildGear gear,
        int act,
        ActGearReviewStatus status,
        CancellationToken cancellationToken = default)
    {
        if (!ActTransitionRules.TrySetReview(
                Run,
                gear,
                act,
                status))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> AdvanceActAsync(
        bool acceptingRouteConsequences,
        CancellationToken cancellationToken = default)
    {
        var currentAct = Run.SelectedAct ?? 1;
        var destination = Payload.Acts.FirstOrDefault(act => act.Act == currentAct + 1);
        if (!ActTransitionRules.TryAdvance(
                Run,
                destination,
                activeGuideLoaded: true,
                Payload.RouteAvailable,
                CurrentActGear,
                CurrentActConsequences,
                acceptingRouteConsequences,
                DateTimeOffset.UtcNow))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }

    public async Task<bool> FinalizeActThreeAsync(
        bool acceptingRouteConsequences,
        CancellationToken cancellationToken = default)
    {
        if (!ActTransitionRules.TryFinalizeActThree(
                Run,
                activeGuideLoaded: true,
                Payload.RouteAvailable,
                RunProgressRules.ActiveSteps(Walkthrough, Run.WalkthroughProgress).Count,
                CurrentActGear,
                CurrentActConsequences,
                acceptingRouteConsequences,
                DateTimeOffset.UtcNow))
        {
            return false;
        }

        await SaveAsync(cancellationToken);
        Notify();
        return true;
    }
}
