using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace BG3HonorAssistant.Core.Models;

public enum Ability
{
    Strength,
    Dexterity,
    Constitution,
    Intelligence,
    Wisdom,
    Charisma,
}

public sealed record AbilityScores(
    int Strength,
    int Dexterity,
    int Constitution,
    int Intelligence,
    int Wisdom,
    int Charisma)
{
    public static AbilityScores CustomDefault { get; } =
        new(17, 15, 14, 10, 10, 8);

    [JsonIgnore]
    public AbilityScores ClampedForPointBuy =>
        new(
            Math.Clamp(Strength, 8, 15),
            Math.Clamp(Dexterity, 8, 15),
            Math.Clamp(Constitution, 8, 15),
            Math.Clamp(Intelligence, 8, 15),
            Math.Clamp(Wisdom, 8, 15),
            Math.Clamp(Charisma, 8, 15));

    [JsonIgnore]
    public string Summary =>
        $"STR {Strength} / DEX {Dexterity} / CON {Constitution} / " +
        $"INT {Intelligence} / WIS {Wisdom} / CHA {Charisma}";

    public int Get(Ability ability) =>
        ability switch
        {
            Ability.Strength => Strength,
            Ability.Dexterity => Dexterity,
            Ability.Constitution => Constitution,
            Ability.Intelligence => Intelligence,
            Ability.Wisdom => Wisdom,
            Ability.Charisma => Charisma,
            _ => throw new ArgumentOutOfRangeException(nameof(ability)),
        };

    public AbilityScores Add(int value, Ability ability) =>
        ability switch
        {
            Ability.Strength => this with { Strength = Strength + value },
            Ability.Dexterity => this with { Dexterity = Dexterity + value },
            Ability.Constitution => this with { Constitution = Constitution + value },
            Ability.Intelligence => this with { Intelligence = Intelligence + value },
            Ability.Wisdom => this with { Wisdom = Wisdom + value },
            Ability.Charisma => this with { Charisma = Charisma + value },
            _ => throw new ArgumentOutOfRangeException(nameof(ability)),
        };

    public static AbilityScores ForClass(string? className) =>
        className?.ToLowerInvariant() switch
        {
            "barbarian" => new(17, 13, 15, 8, 12, 10),
            "bard" => new(8, 15, 13, 12, 10, 17),
            "cleric" or "druid" => new(10, 14, 15, 8, 17, 10),
            "fighter" => new(17, 13, 15, 10, 12, 8),
            "monk" => new(12, 17, 14, 8, 14, 10),
            "paladin" => new(17, 10, 13, 8, 10, 16),
            "ranger" => new(10, 17, 14, 8, 16, 8),
            "rogue" => new(8, 17, 14, 13, 13, 10),
            "sorcerer" => new(8, 13, 15, 12, 10, 17),
            "warlock" => new(8, 14, 14, 12, 10, 17),
            "wizard" => new(8, 13, 15, 17, 10, 12),
            _ => CustomDefault,
        };
}

public enum AbilityModifierKind
{
    Permanent,
    Temporary,
    Equipment,
}

public enum AbilityModifierMode
{
    Add,
    Minimum,
}

public enum AbilityPlanSourceKind
{
    Asi,
    Feat,
    Permanent,
    Equipment,
    Consumable,
}

public sealed record AbilityPlanSource
{
    public required string Id { get; init; }

    public required Ability Ability { get; init; }

    public required AbilityPlanSourceKind Kind { get; init; }

    public required AbilityModifierMode Mode { get; init; }

    public required int Value { get; init; }

    public required string Label { get; init; }

    [JsonPropertyName("minimum_act")]
    public int MinimumAct { get; init; } = 1;

    [JsonPropertyName("minimum_level")]
    public int MinimumLevel { get; init; } = 1;

    [JsonPropertyName("maximum_level")]
    public int? MaximumLevel { get; init; }

    [JsonPropertyName("item_key")]
    public string? ItemKey { get; init; }

    [JsonPropertyName("unique_across_party")]
    public bool UniqueAcrossParty { get; init; }

    public string Note { get; init; } = string.Empty;

    public bool AppliesAt(int level) =>
        level >= MinimumLevel && (MaximumLevel is null || level <= MaximumLevel);
}

public sealed record AbilityModifier(
    Ability Ability,
    AbilityModifierKind Kind,
    AbilityModifierMode Mode,
    int Value,
    string Source)
{
    public string Id { get; init; } = Guid.NewGuid().ToString();

    public string? PlanSourceId { get; init; }
}

public sealed record AbilityBreakdown(
    Ability Ability,
    int Starting,
    int LevelGain,
    int Permanent,
    int Equipment,
    int Temporary,
    int Current,
    int Target)
{
    [JsonIgnore]
    public int Normal => Starting + LevelGain;

    [JsonIgnore]
    public string Tooltip
    {
        get
        {
            var parts = new List<string> { $"{Starting} starting" };
            if (LevelGain > 0) parts.Add($"+ {LevelGain} feat / ASI");
            if (Permanent > 0) parts.Add($"+ {Permanent} permanent");
            if (Equipment > 0) parts.Add($"+ {Equipment} equipment");
            if (Temporary > 0) parts.Add($"+ {Temporary} temporary");
            var missing = Math.Max(0, Target - Current);
            var targetStatus = missing > 0
                ? $"{missing} planned before the build goal of {Target}."
                : Current > Target
                    ? $"{Current - Target} above the build goal of {Target}."
                    : $"Build goal: {Target}.";
            return
                $"{Ability}: {string.Join(" ", parts)} = {Current}. {targetStatus}";
        }
    }
}

public sealed record AbilitySetupPlan
{
    public required string Id { get; init; }

    public required int Level { get; init; }

    public required string Label { get; init; }

    public required string Reason { get; init; }

    [JsonPropertyName("point_buy_scores")]
    public required AbilityScores PointBuyScores { get; init; }

    [JsonPropertyName("bonus_two")]
    public required Ability BonusTwo { get; init; }

    [JsonPropertyName("bonus_one")]
    public required Ability BonusOne { get; init; }

    [JsonPropertyName("final_scores")]
    public required AbilityScores FinalScores { get; init; }

    [JsonPropertyName("first_class")]
    public required string FirstClass { get; init; }

    [JsonPropertyName("class_order")]
    public required string ClassOrder { get; init; }
}

public static class AbilityProgression
{
    private static readonly IReadOnlyDictionary<int, int> PointBuyCosts =
        new Dictionary<int, int>
        {
            [8] = 0,
            [9] = 1,
            [10] = 2,
            [11] = 3,
            [12] = 4,
            [13] = 5,
            [14] = 7,
            [15] = 9,
        };

    public static int PointBuyCost(AbilityScores scores)
    {
        var values = Enum.GetValues<Ability>().Select(scores.Get).ToArray();
        return values.All(PointBuyCosts.ContainsKey)
            ? values.Sum(value => PointBuyCosts[value])
            : -1;
    }

    public static bool IsValidBg3Setup(AbilitySetupPlan setup)
    {
        if (setup.BonusTwo == setup.BonusOne ||
            PointBuyCost(setup.PointBuyScores) != 27)
        {
            return false;
        }

        return Enum.GetValues<Ability>().All(
            ability =>
            {
                var bonus = ability == setup.BonusTwo
                    ? 2
                    : ability == setup.BonusOne
                        ? 1
                        : 0;
                return setup.FinalScores.Get(ability) ==
                       setup.PointBuyScores.Get(ability) + bonus;
            });
    }

    public static AbilitySetupPlan? ActiveSetup(BuildSummary? build, int level) =>
        build?.AbilitySetups?
            .Where(setup => setup.Level <= level)
            .OrderBy(setup => setup.Level)
            .LastOrDefault();

    public static int ModifierFor(int score) =>
        (int)Math.Floor((score - 10) / 2.0);

    public static AbilityBreakdown Breakdown(
        PartyMember member,
        BuildSummary? build,
        Ability ability,
        IReadOnlySet<string>? equippedItemKeys = null)
    {
        equippedItemKeys ??= new HashSet<string>();
        var currentLevels = build?.Levels
            .Where(level => level.Level <= member.Level)
            .ToList() ?? [];
        var activeSetup = ActiveSetup(build, member.Level);
        var currentReset = activeSetup is null
            ? currentLevels.LastOrDefault(level => level.AbilityScoreReset is not null)
            : null;
        var recommendedScores =
            activeSetup?.FinalScores ??
            currentReset?.AbilityScoreReset ??
            build?.StartingAbilityScores;
        var startingScores =
            member.AbilityScores ??
            recommendedScores ??
            member.EffectiveAbilityScores;
        var starting = startingScores.Get(ability);
        var structuredSources = build?.AbilitySources ?? [];
        var hasAppliedBuildSetup =
            member.AppliedAbilitySetupId is { } appliedId &&
            build?.AbilitySetups?.Any(setup => setup.Id == appliedId) == true;
        var levelGain = structuredSources.Count == 0
            ? AbilityGain(
                currentLevels.Where(
                    level => level.Level > (currentReset?.Level ?? 0)),
                ability)
            : hasAppliedBuildSetup
                ? SourceGain(
                    structuredSources,
                    ability,
                    member.Level,
                    AbilityPlanSourceKind.Asi,
                    AbilityPlanSourceKind.Feat)
                : 0;

        var finalLevels = build?.Levels ?? currentLevels;
        var finalReset = finalLevels.LastOrDefault(
            level => level.AbilityScoreReset is not null);
        var finalStarting =
            (finalReset?.AbilityScoreReset ?? startingScores).Get(ability);
        var finalGain = structuredSources.Count == 0
            ? AbilityGain(
                finalLevels.Where(
                    level => level.Level > (finalReset?.Level ?? 0)),
                ability)
            : SourceGain(
                structuredSources,
                ability,
                12,
                AbilityPlanSourceKind.Asi,
                AbilityPlanSourceKind.Feat);
        var modifiers = (member.AbilityModifiers ?? [])
            .Where(modifier => modifier.Ability == ability)
            .ToList();

        var running = starting + levelGain;
        var permanent = Contribution(
            AbilityModifierKind.Permanent,
            modifiers,
            ref running);
        var beforeEquipment = running;
        foreach (var source in structuredSources.Where(
                     source =>
                         source.Ability == ability &&
                         source.Kind == AbilityPlanSourceKind.Equipment &&
                         source.AppliesAt(member.Level) &&
                         source.ItemKey is { } itemKey &&
                         equippedItemKeys.Contains(itemKey)))
        {
            Apply(source.Mode, source.Value, ref running);
        }

        _ = Contribution(
            AbilityModifierKind.Equipment,
            modifiers,
            ref running);
        var equipment = running - beforeEquipment;
        var temporary = Contribution(
            AbilityModifierKind.Temporary,
            modifiers,
            ref running);
        var target =
            build?.TargetAbilityScores?.Get(ability) ??
            finalStarting + finalGain;
        return new AbilityBreakdown(
            ability,
            starting,
            levelGain,
            permanent,
            equipment,
            temporary,
            running,
            target);
    }

    public static BuildLevel? NextFeat(BuildSummary? build, int afterLevel) =>
        build?.Levels.FirstOrDefault(
            level => level.Level > afterLevel && IsAbilityChoice(level.Choices));

    private static int Contribution(
        AbilityModifierKind kind,
        IReadOnlyList<AbilityModifier> modifiers,
        ref int running)
    {
        var before = running;
        foreach (var modifier in modifiers.Where(
                     modifier =>
                         modifier.Kind == kind &&
                         modifier.Mode == AbilityModifierMode.Add))
        {
            running += modifier.Value;
        }

        foreach (var modifier in modifiers.Where(
                     modifier =>
                         modifier.Kind == kind &&
                         modifier.Mode == AbilityModifierMode.Minimum))
        {
            running = Math.Max(running, modifier.Value);
        }

        return running - before;
    }

    private static void Apply(
        AbilityModifierMode mode,
        int value,
        ref int running)
    {
        running = mode == AbilityModifierMode.Add
            ? running + value
            : Math.Max(running, value);
    }

    private static int SourceGain(
        IEnumerable<AbilityPlanSource> sources,
        Ability ability,
        int level,
        params AbilityPlanSourceKind[] kinds)
    {
        var total = 0;
        foreach (var source in sources.Where(
                     source =>
                         source.Ability == ability &&
                         kinds.Contains(source.Kind) &&
                         source.AppliesAt(level)))
        {
            total = source.Mode == AbilityModifierMode.Add
                ? total + source.Value
                : Math.Max(total, source.Value);
        }

        return total;
    }

    private static int AbilityGain(
        IEnumerable<BuildLevel> levels,
        Ability ability) =>
        levels.Sum(level => ExplicitGain(level.Choices, ability));

    private static int ExplicitGain(string choices, Ability ability)
    {
        var aliases = new[]
        {
            ability.ToString()[..3].ToUpperInvariant(),
            ability.ToString(),
        };
        var total = 0;
        foreach (var alias in aliases)
        {
            foreach (var pattern in new[]
                     {
                         $@"\+(\d+)\s*{Regex.Escape(alias)}\b",
                         $@"\b{Regex.Escape(alias)}\s*\+(\d+)\b",
                     })
            {
                total += Regex
                    .Matches(
                        choices,
                        pattern,
                        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
                    .Select(match => int.Parse(match.Groups[1].Value))
                    .Sum();
            }
        }

        if (total != 0)
        {
            return total;
        }

        var lower = choices.ToLowerInvariant();
        if (ability == Ability.Wisdom && lower.Contains("resilient: wisdom"))
        {
            return 1;
        }

        if (ability == Ability.Charisma && lower.Contains("actor"))
        {
            return 1;
        }

        return ability == Ability.Strength &&
               lower.Contains("heavy armour master")
            ? 1
            : 0;
    }

    private static bool IsAbilityChoice(string choices)
    {
        var lower = choices.ToLowerInvariant();
        return lower.Contains("asi") ||
               lower.Contains("ability improvement") ||
               lower.Contains("feat") ||
               lower.Contains("tavern brawler") ||
               lower.Contains("resilient:") ||
               lower.Contains("actor") ||
               lower.Contains("savage attacker") ||
               lower.Contains("sharpshooter") ||
               lower.Contains("dual wielder") ||
               lower.Contains("war caster") ||
               lower.Contains("alert") ||
               Regex.IsMatch(
                   lower,
                   @"\+\d+\s+(str|dex|con|int|wis|cha)",
                   RegexOptions.CultureInvariant);
    }
}
