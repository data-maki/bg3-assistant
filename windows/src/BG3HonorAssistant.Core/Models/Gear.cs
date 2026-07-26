using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace BG3HonorAssistant.Core.Models;

public sealed record BuildGear
{
    public required string Item { get; init; }

    public required string Slot { get; init; }

    public required string Priority { get; init; }

    public required int Act { get; init; }

    public required string Region { get; init; }

    public required string Acquisition { get; init; }

    public required string Why { get; init; }

    public required string Source { get; init; }

    public int? MinimumLevel { get; init; }

    public int? MaximumLevel { get; init; }

    public string? Requirement { get; init; }

    [JsonPropertyName("map_objective")]
    public bool? MapObjective { get; init; }

    public string? Alternative { get; init; }

    public string? Effect { get; init; }

    public string? Acquire { get; init; }

    public string? Wiki { get; init; }

    public string? Icon { get; init; }

    [JsonPropertyName("game_x")]
    public int? GameX { get; init; }

    [JsonPropertyName("game_y")]
    public int? GameY { get; init; }

    [JsonIgnore]
    public string Id => $"{Item}|{Region}";

    public bool IsAvailableAt(int level) =>
        level >= (MinimumLevel ?? 1) &&
        (MaximumLevel is null || level <= MaximumLevel);

    [JsonIgnore]
    public bool IsMapObjective => MapObjective ?? true;

    [JsonIgnore]
    public string ItemKey =>
        Regex.Replace(
                Regex.Replace(Item, @"\s*x\d+$", string.Empty).ToLowerInvariant(),
                @"[^a-z0-9]+",
                "-")
            .Trim('-');
}

public sealed record GearTarget(string MemberId, string BuildId, string GearId);

public enum LoadoutSlot
{
    Helmet,
    Cloak,
    Armour,
    Gloves,
    Boots,
    Instrument,
    Amulet,
    Rings,
    MainHand,
    OffHand,
    Ranged,
    Extras,
}

public static class LoadoutSlotExtensions
{
    public static string Id(this LoadoutSlot slot) =>
        slot switch
        {
            LoadoutSlot.Helmet => "Helmet",
            LoadoutSlot.Cloak => "Cape",
            LoadoutSlot.Armour => "Armour",
            LoadoutSlot.Gloves => "Gloves",
            LoadoutSlot.Boots => "Boots",
            LoadoutSlot.Instrument => "Instrument",
            LoadoutSlot.Amulet => "Amulet",
            LoadoutSlot.Rings => "Rings",
            LoadoutSlot.MainHand => "Main hand",
            LoadoutSlot.OffHand => "Off-hand",
            LoadoutSlot.Ranged => "Ranged",
            LoadoutSlot.Extras => "Camp & consumables",
            _ => throw new ArgumentOutOfRangeException(nameof(slot)),
        };

    public static string Label(this LoadoutSlot slot) =>
        slot switch
        {
            LoadoutSlot.Armour => "Armor",
            LoadoutSlot.Boots => "Shoes",
            LoadoutSlot.Amulet => "Necklace",
            LoadoutSlot.Rings => "Ring",
            LoadoutSlot.MainHand => "Sword",
            LoadoutSlot.OffHand => "Shield / 2nd Sword",
            LoadoutSlot.Ranged => "Bow",
            _ => slot.Id(),
        };
}

public readonly record struct DollCell(LoadoutSlot Slot, int Field = 0)
{
    public string Id => $"{Slot.Id()}#{Field}";

    public string Label => Slot == LoadoutSlot.Rings
        ? $"Ring {Field + 1}"
        : Slot.Label();

    public string EmptyLabel => $"{Label}: no pick";

    public static IReadOnlyList<IReadOnlyList<DollCell>> PaperDollRows { get; } =
    [
        [new(LoadoutSlot.Helmet), new(LoadoutSlot.Amulet)],
        [new(LoadoutSlot.Cloak), new(LoadoutSlot.Rings, 0)],
        [new(LoadoutSlot.Armour), new(LoadoutSlot.Rings, 1)],
        [new(LoadoutSlot.Gloves), new(LoadoutSlot.MainHand)],
        [new(LoadoutSlot.Boots), new(LoadoutSlot.OffHand)],
        [new(LoadoutSlot.Instrument), new(LoadoutSlot.Ranged)],
    ];

    public IReadOnlyList<BuildGear> Items(
        IReadOnlyDictionary<LoadoutSlot, IReadOnlyList<BuildGear>> grouped)
    {
        var items = grouped.GetValueOrDefault(Slot) ?? [];
        if (Slot != LoadoutSlot.Rings)
        {
            return items;
        }

        return Field == 0 ? items.Take(1).ToList() : items.Skip(1).ToList();
    }
}

public static class LoadoutSlotClassifier
{
    public static LoadoutSlot Classify(string tsvSlot, string item)
    {
        if (item.Contains("torch", StringComparison.OrdinalIgnoreCase))
        {
            return LoadoutSlot.Extras;
        }

        var slot = tsvSlot.ToLowerInvariant();
        if (slot.Contains("head", StringComparison.Ordinal)) return LoadoutSlot.Helmet;
        if (slot.Contains("cloak", StringComparison.Ordinal) ||
            slot.Contains("cape", StringComparison.Ordinal)) return LoadoutSlot.Cloak;
        if (slot.Contains("chest", StringComparison.Ordinal)) return LoadoutSlot.Armour;
        if (slot.Contains("off-hand", StringComparison.Ordinal) ||
            slot.Contains("shield", StringComparison.Ordinal)) return LoadoutSlot.OffHand;
        if (slot.Contains("hands", StringComparison.Ordinal)) return LoadoutSlot.Gloves;
        if (slot.Contains("feet", StringComparison.Ordinal)) return LoadoutSlot.Boots;
        if (slot.Contains("instrument", StringComparison.Ordinal)) return LoadoutSlot.Instrument;
        if (slot.Contains("amulet", StringComparison.Ordinal)) return LoadoutSlot.Amulet;
        if (slot.Contains("ring", StringComparison.Ordinal)) return LoadoutSlot.Rings;
        if (slot.Contains("ranged", StringComparison.Ordinal)) return LoadoutSlot.Ranged;
        if (slot.Contains("melee", StringComparison.Ordinal)) return LoadoutSlot.MainHand;
        return LoadoutSlot.Extras;
    }
}

public sealed record GearClaim(
    string MemberId,
    string MemberName,
    string BuildName,
    DateTimeOffset? BuildAssignedAt,
    IReadOnlySet<string> ItemKeys);

public enum GearPathRowKind
{
    LevelGate,
    Step,
    Info,
    Acquisition,
}

public sealed record GearPathRow(
    GearPathRowKind Kind,
    int? RequiredLevel = null,
    int? PartyLevel = null,
    WalkthroughStep? Step = null,
    bool? Done = null,
    string? Text = null);

public sealed record GearPickup(
    BuildGear Gear,
    string MemberId,
    string MemberName)
{
    public string Id => $"{MemberId}|{Gear.ItemKey}";
}

public sealed record GearPickupGroups(
    IReadOnlyDictionary<int, IReadOnlyList<GearPickup>> ByPhase,
    IReadOnlyList<GearPickup> Other);

public enum GearRegionCluster
{
    Wilderness,
    Settlement,
    Hostile,
    Underdark,
    Forge,
    MountainPass,
    Rivington,
    Other,
}

public static class GearLogic
{
    private sealed record RegionStage(
        IReadOnlyList<string> Keywords,
        GearRegionCluster Cluster);

    private static readonly IReadOnlyDictionary<int, IReadOnlyList<RegionStage>> RegionStages =
        new Dictionary<int, IReadOnlyList<RegionStage>>
        {
            [1] =
            [
                Stage(GearRegionCluster.Other, "nautiloid"),
                Stage(GearRegionCluster.Other, "anywhere"),
                Stage(GearRegionCluster.Wilderness, "druid grove"),
                Stage(GearRegionCluster.Settlement, "blighted village"),
                Stage(GearRegionCluster.Settlement, "apothecary"),
                Stage(GearRegionCluster.Hostile, "goblin camp", "shattered sanctum"),
                Stage(GearRegionCluster.Settlement, "waukeen"),
                Stage(GearRegionCluster.Wilderness, "sunlit wetlands", "riverside teahouse"),
                Stage(GearRegionCluster.Wilderness, "risen road"),
                Stage(GearRegionCluster.Hostile, "zhentarim"),
                Stage(GearRegionCluster.Underdark, "selûnite outpost"),
                Stage(GearRegionCluster.Underdark, "myconid colony"),
                Stage(GearRegionCluster.Underdark, "underdark"),
                Stage(GearRegionCluster.Forge, "grymforge"),
                Stage(GearRegionCluster.Forge, "adamantine forge"),
                Stage(GearRegionCluster.MountainPass, "rosymorn monastery trail"),
                Stage(GearRegionCluster.MountainPass, "rosymorn monastery"),
                Stage(GearRegionCluster.MountainPass, "crèche y'llek"),
            ],
            [2] =
            [
                Stage(GearRegionCluster.Underdark, "ruined battlefield"),
                Stage(GearRegionCluster.Wilderness, "last light inn"),
                Stage(GearRegionCluster.Settlement, "reithwin"),
                Stage(GearRegionCluster.Hostile, "moonrise towers", "moonrise"),
                Stage(GearRegionCluster.Underdark, "gauntlet of shar"),
                Stage(GearRegionCluster.Hostile, "mind flayer colony", "mind flayer"),
            ],
            [3] =
            [
                Stage(
                    GearRegionCluster.Rivington,
                    "rivington",
                    "circus of the last days",
                    "circus"),
                Stage(GearRegionCluster.Settlement, "lower city"),
                Stage(GearRegionCluster.Settlement, "sorcerous sundries", "ramazith"),
                Stage(GearRegionCluster.Hostile, "cazador"),
                Stage(GearRegionCluster.Hostile, "murder tribunal"),
                Stage(GearRegionCluster.Hostile, "house of hope"),
            ],
        };

    public static IReadOnlyDictionary<string, string> Assignments(
        IReadOnlyList<GearClaim> claims,
        IReadOnlyDictionary<string, string> overrides)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var allKeys = claims.SelectMany(claim => claim.ItemKeys).ToHashSet(StringComparer.Ordinal);

        foreach (var key in allKeys)
        {
            var claimants = claims.Where(claim => claim.ItemKeys.Contains(key)).ToArray();
            if (overrides.TryGetValue(key, out var chosen) &&
                claimants.Any(claim => claim.MemberId == chosen))
            {
                result[key] = chosen;
                continue;
            }

            var winner = claimants
                .OrderBy(claim => claim.BuildAssignedAt ?? DateTimeOffset.MaxValue)
                .ThenBy(claim => claim.BuildName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(claim => claim.MemberName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(claim => claim.MemberId, StringComparer.Ordinal)
                .First();
            result[key] = winner.MemberId;
        }

        return result;
    }

    public static int RouteRank(string region, int act)
    {
        if (!RegionStages.TryGetValue(act, out var stages))
        {
            return 0;
        }

        var normalized = region.ToLowerInvariant();
        for (var index = 0; index < stages.Count; index++)
        {
            if (stages[index].Keywords.Any(normalized.Contains))
            {
                return index;
            }
        }

        return stages.Count;
    }

    public static GearRegionCluster RegionCluster(string region)
    {
        var normalized = region.ToLowerInvariant();
        foreach (var act in RegionStages.Keys.Order())
        {
            var match = RegionStages[act].FirstOrDefault(
                stage => stage.Keywords.Any(normalized.Contains));
            if (match is not null)
            {
                return match.Cluster;
            }
        }

        return GearRegionCluster.Other;
    }

    public static IReadOnlyList<string> RegionParts(string region) =>
        region.Split('/')
            .Select(part => part.Trim())
            .Where(part => part.Length > 0)
            .ToList();

    public static IReadOnlyList<WalkthroughStep> MatchingSteps(
        BuildGear gear,
        IReadOnlyList<WalkthroughStep> walkthrough)
    {
        var parts = RegionParts(gear.Region)
            .Select(part => part.ToLowerInvariant())
            .ToList();
        if (parts.Count == 0)
        {
            return [];
        }

        return walkthrough
            .Where(
                step =>
                {
                    var fields = new[] { step.Area, step.Region }
                        .Select(field => field.ToLowerInvariant())
                        .Where(field => field.Length > 0);
                    return parts.Any(
                        part => fields.Any(
                            field =>
                                field.Contains(part, StringComparison.Ordinal) ||
                                part.Contains(field, StringComparison.Ordinal)));
                })
            .OrderBy(step => step.Order)
            .ToList();
    }

    public static IReadOnlyList<GearPathRow> PathRows(
        BuildGear gear,
        int memberLevel,
        IReadOnlyList<WalkthroughStep> walkthrough,
        IReadOnlyDictionary<string, CheckpointDisposition> dispositions)
    {
        var rows = new List<GearPathRow>();
        if (gear.MinimumLevel is { } minimum && memberLevel < minimum)
        {
            rows.Add(
                new GearPathRow(
                    GearPathRowKind.LevelGate,
                    RequiredLevel: minimum,
                    PartyLevel: memberLevel));
        }

        rows.AddRange(
            MatchingSteps(gear, walkthrough)
                .Select(
                    step => new GearPathRow(
                        GearPathRowKind.Step,
                        Step: step,
                        Done: dispositions.GetValueOrDefault(step.Id) ==
                              CheckpointDisposition.Completed)));

        if (!string.IsNullOrEmpty(gear.Requirement))
        {
            rows.Add(new GearPathRow(GearPathRowKind.Info, Text: gear.Requirement));
        }

        rows.Add(new GearPathRow(GearPathRowKind.Acquisition, Text: AcquireText(gear)));
        return rows;
    }

    public static string AcquireText(BuildGear gear) =>
        !string.IsNullOrEmpty(gear.Acquire) ? gear.Acquire : gear.Acquisition;

    public static GearPickupGroups PickupsByPhase(
        IReadOnlyList<GearPickup> pickups,
        IReadOnlyList<WalkthroughStep> walkthrough)
    {
        var byPhase = new Dictionary<int, List<GearPickup>>();
        var other = new List<GearPickup>();
        foreach (var pickup in pickups)
        {
            var first = MatchingSteps(pickup.Gear, walkthrough).FirstOrDefault();
            if (first is null)
            {
                other.Add(pickup);
                continue;
            }

            if (!byPhase.TryGetValue(first.PhaseOrder, out var phasePickups))
            {
                phasePickups = [];
                byPhase[first.PhaseOrder] = phasePickups;
            }

            phasePickups.Add(pickup);
        }

        return new GearPickupGroups(
            byPhase.ToDictionary(
                pair => pair.Key,
                pair => (IReadOnlyList<GearPickup>)pair.Value),
            other);
    }

    public static int PriorityRank(string priority)
    {
        string[] ranks =
        [
            "Required",
            "Core",
            "Upgrade",
            "Starter",
            "Support",
            "Defence",
            "Supply",
            "Intentional",
            "Optional",
            "Endgame",
        ];
        var index = Array.IndexOf(ranks, priority);
        return index < 0 ? 99 : index;
    }

    private static RegionStage Stage(
        GearRegionCluster cluster,
        params string[] keywords) =>
        new(keywords, cluster);
}
