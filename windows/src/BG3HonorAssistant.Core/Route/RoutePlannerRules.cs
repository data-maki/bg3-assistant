using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Route;

public enum RouteContentFilter
{
    All,
    Core,
    Equipment,
}

public enum RoutePlannerRowKind
{
    Phase,
    Step,
    Gear,
    OtherGear,
}

public sealed record RoutePlannerRow(
    RoutePlannerRowKind Kind,
    string Label,
    string Meta,
    string Status,
    int PhaseOrder,
    WalkthroughStep? Step = null,
    GearPickup? Pickup = null)
{
    public bool IsSelectable => Step is not null || Pickup is not null;
}

public sealed record ArchivedRouteRow(
    WalkthroughStep Step,
    CheckpointDisposition Disposition)
{
    public string Label => Step.Title;

    public string Meta =>
        $"{Disposition.ToString().ToUpperInvariant()} - {Step.Phase} - {Step.Area}";
}

public sealed record RoutePlannerPresentation(
    int ArchivedCount,
    int TotalCount,
    IReadOnlyList<RoutePlannerRow> Rows,
    IReadOnlyList<ArchivedRouteRow> Archived,
    bool SpoilerLight)
{
    public double Progress =>
        TotalCount == 0 ? 0D : ArchivedCount / (double)TotalCount;
}

public static class RoutePlannerRules
{
    public static RoutePlannerPresentation Present(
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition>? progress,
        IReadOnlyDictionary<string, string>? outcomes,
        RouteRevealPolicy revealPolicy,
        IReadOnlyList<GearPickup> pickups,
        RouteContentFilter filter,
        WalkthroughStep? currentStep,
        int lowestPartyLevel)
    {
        var state = progress ??
                    new Dictionary<string, CheckpointDisposition>(
                        StringComparer.Ordinal);
        var active = RunProgressRules.ActiveSteps(walkthrough, state);
        var visible = RunProgressRules.VisibleSteps(
            walkthrough,
            state,
            revealPolicy);
        var filteredSteps = filter switch
        {
            RouteContentFilter.All => visible,
            RouteContentFilter.Core =>
                visible.Where(step => step.Importance != "optional").ToList(),
            RouteContentFilter.Equipment => [],
            _ => throw new ArgumentOutOfRangeException(nameof(filter)),
        };
        var groupedPickups = GearLogic.PickupsByPhase(pickups, walkthrough);
        var pickupPhases = filter == RouteContentFilter.Core
            ? new HashSet<int>()
            : groupedPickups.ByPhase.Keys.ToHashSet();
        var stepPhases = filteredSteps.Select(step => step.PhaseOrder).ToHashSet();
        var phaseOrders = stepPhases.Union(pickupPhases).Order().ToList();
        var rows = new List<RoutePlannerRow>();

        foreach (var phaseOrder in phaseOrders)
        {
            var steps = filteredSteps
                .Where(step => step.PhaseOrder == phaseOrder)
                .OrderBy(step => step.Order)
                .ToList();
            var phasePickups = filter == RouteContentFilter.Core
                ? []
                : groupedPickups.ByPhase.GetValueOrDefault(phaseOrder) ?? [];
            var phaseName = steps.FirstOrDefault()?.Phase ??
                            walkthrough.FirstOrDefault(
                                step => step.PhaseOrder == phaseOrder)?.Phase ??
                            "Other";
            rows.Add(
                new RoutePlannerRow(
                    RoutePlannerRowKind.Phase,
                    phaseName.ToUpperInvariant(),
                    PhaseCount(filter, steps.Count, phasePickups.Count),
                    string.Empty,
                    phaseOrder));

            foreach (var step in steps)
            {
                var dependency = RunSafety.DependencyPresentation(
                    step,
                    walkthrough,
                    state,
                    outcomes,
                    currentStep,
                    active);
                var status = step.Id == currentStep?.Id
                    ? "NOW"
                    : dependency.RequiresAttention
                        ? "REVISIT"
                        : dependency.Note is not null
                            ? "LATER"
                            : step.MinimumLevel > lowestPartyLevel
                                ? $"L{step.MinimumLevel}"
                                : "READY";
                rows.Add(
                    new RoutePlannerRow(
                        RoutePlannerRowKind.Step,
                        step.Title,
                        dependency.Note ?? step.Area,
                        status,
                        phaseOrder,
                        Step: step));
            }

            foreach (var pickup in phasePickups)
            {
                rows.Add(
                    new RoutePlannerRow(
                        RoutePlannerRowKind.Gear,
                        pickup.Gear.Item,
                        $"For {pickup.MemberName} - {pickup.Gear.Region}",
                        pickup.Gear.Priority.ToUpperInvariant(),
                        phaseOrder,
                        Pickup: pickup));
            }
        }

        if (filter != RouteContentFilter.Core &&
            groupedPickups.Other.Count > 0)
        {
            rows.Add(
                new RoutePlannerRow(
                    RoutePlannerRowKind.Phase,
                    "OTHER PICKUPS",
                    $"{groupedPickups.Other.Count} item" +
                    (groupedPickups.Other.Count == 1 ? string.Empty : "s"),
                    string.Empty,
                    int.MaxValue));
            rows.AddRange(
                groupedPickups.Other.Select(
                    pickup => new RoutePlannerRow(
                        RoutePlannerRowKind.OtherGear,
                        pickup.Gear.Item,
                        $"For {pickup.MemberName} - {pickup.Gear.Region}",
                        pickup.Gear.Priority.ToUpperInvariant(),
                        int.MaxValue,
                        Pickup: pickup)));
        }

        var archived = RunProgressRules.ArchivedSteps(walkthrough, state)
            .Select(
                step => new ArchivedRouteRow(
                    step,
                    RunSafety.WalkthroughDisposition(step, state)))
            .OrderBy(row => row.Step.Order)
            .ToList();
        return new RoutePlannerPresentation(
            archived.Count,
            walkthrough.Count,
            rows,
            archived,
            revealPolicy == RouteRevealPolicy.NextThree);
    }

    private static string PhaseCount(
        RouteContentFilter filter,
        int stepCount,
        int pickupCount) =>
        filter switch
        {
            RouteContentFilter.All =>
                $"{stepCount} route - {pickupCount} gear",
            RouteContentFilter.Core =>
                $"{stepCount} core",
            RouteContentFilter.Equipment =>
                $"{pickupCount} item" + (pickupCount == 1 ? string.Empty : "s"),
            _ => throw new ArgumentOutOfRangeException(nameof(filter)),
        };
}
