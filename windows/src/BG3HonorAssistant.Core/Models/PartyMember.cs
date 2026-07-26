using System.Text.Json.Serialization;

namespace BG3HonorAssistant.Core.Models;

public sealed record PartyMember
{
    public required string Id { get; init; }

    public required string Name { get; init; }

    public required int Level { get; init; }

    public string? BuildId { get; init; }

    public IReadOnlyList<string> PreparedTags { get; init; } = [];

    public string? ClassName { get; init; }

    public RosterStatus? Status { get; init; }

    public string? RoleOverride { get; init; }

    public bool? IsCustom { get; init; }

    public AbilityScores? AbilityScores { get; init; }

    public bool? IsHireling { get; init; }

    public string? SourceLoadoutId { get; init; }

    public IReadOnlyList<AbilityModifier>? AbilityModifiers { get; init; }

    public bool? UsesBuildAbilityScores { get; init; }

    public string? AppliedAbilitySetupId { get; init; }

    public ManualBuildPlan? ManualBuild { get; init; }

    [JsonIgnore]
    public RosterStatus RosterStatus => Status ?? RosterStatus.Active;

    [JsonIgnore]
    public AbilityScores EffectiveAbilityScores =>
        AbilityScores ?? Models.AbilityScores.ForClass(ClassName);
}

public enum RosterStatus
{
    Active,
    Camp,
    Unrecruited,
    Unavailable,
    Dead,
    Departed,
}

public static class RosterStatusExtensions
{
    public static bool CanBeActive(this RosterStatus status) =>
        status is RosterStatus.Active or RosterStatus.Camp or RosterStatus.Unrecruited;
}

public sealed record StoryCompanion(string Name, string DefaultClass);

public static class StoryCompanionCatalog
{
    public static IReadOnlyList<StoryCompanion> Origins { get; } =
    [
        new("Shadowheart", "Cleric"),
        new("Lae'zel", "Fighter"),
        new("Astarion", "Rogue"),
        new("Gale", "Wizard"),
        new("Wyll", "Warlock"),
        new("Karlach", "Barbarian"),
        new("Dark Urge", "Sorcerer"),
    ];

    public static IReadOnlyList<StoryCompanion> Recruitable { get; } =
    [
        new("Halsin", "Druid"),
        new("Minthara", "Paladin"),
        new("Jaheira", "Druid"),
        new("Minsc", "Ranger"),
    ];

    public static IReadOnlyList<StoryCompanion> All { get; } =
        Origins.Concat(Recruitable).ToList();

    public static StoryCompanion? Matching(string name) =>
        All.FirstOrDefault(
            companion =>
                string.Equals(
                    companion.Name,
                    name,
                    StringComparison.OrdinalIgnoreCase));
}

public sealed record WithersHireling(
    string Name,
    string Race,
    string DefaultClass)
{
    [JsonIgnore]
    public AbilityScores DefaultAbilityScores => Models.AbilityScores.ForClass(DefaultClass);
}

public static class WithersHirelingCatalog
{
    public static IReadOnlyList<WithersHireling> All { get; } =
    [
        new("Eldra Luthrinn", "Gold Dwarf", "Barbarian"),
        new("Brinna Brightsong", "Lightfoot Halfling", "Bard"),
        new("Zenith Feur'sel", "High Elf", "Cleric"),
        new("Danton", "Mephistopheles Tiefling", "Druid"),
        new("Varanna Sunblossom", "Wood Half-Elf", "Fighter"),
        new("Sina'zith", "Githyanki", "Monk"),
        new("Kerz", "Half-Orc", "Paladin"),
        new("Ver'yll Wenkiir", "Seldarine Drow", "Ranger"),
        new("Maddala Deadeye", "Human", "Rogue"),
        new("Jacelyn", "High Half-Elf", "Sorcerer"),
        new("Kree Derryck", "Duergar", "Warlock"),
        new("Sir Fuzzalump", "Rock Gnome", "Wizard"),
    ];

    public static WithersHireling? Matching(string name) =>
        All.FirstOrDefault(
            hireling =>
                string.Equals(
                    hireling.Name,
                    name,
                    StringComparison.OrdinalIgnoreCase));
}
