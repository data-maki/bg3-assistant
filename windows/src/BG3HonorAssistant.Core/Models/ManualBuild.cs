using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace BG3HonorAssistant.Core.Models;

public sealed record ManualBuildLevel
{
    public required int CharacterLevel { get; init; }

    public string ClassName { get; set; } = string.Empty;

    public Dictionary<string, IReadOnlyList<string>> Selections { get; set; } = [];
}

public sealed record ManualBuildPlan
{
    public required string Name { get; init; }

    public required AbilityScores AbilityScores { get; init; }

    public required List<ManualBuildLevel> Levels { get; init; }

    public static ManualBuildPlan Empty(string name, AbilityScores scores) =>
        new()
        {
            Name = name,
            AbilityScores = scores,
            Levels = Enumerable.Range(1, 12)
                .Select(
                    level => new ManualBuildLevel
                    {
                        CharacterLevel = level,
                    })
                .ToList(),
        };

    public int ClassLevel(int characterLevel)
    {
        var selectedClass = Levels
            .FirstOrDefault(level => level.CharacterLevel == characterLevel)?
            .ClassName;
        return string.IsNullOrEmpty(selectedClass)
            ? 0
            : Levels.Count(
                level => level.CharacterLevel <= characterLevel &&
                         level.ClassName == selectedClass);
    }

    public void SetClass(string className, int characterLevel)
    {
        var index = Levels.FindIndex(level => level.CharacterLevel == characterLevel);
        if (index < 0)
        {
            return;
        }

        var replacedClass = Levels[index].ClassName;
        if (replacedClass == className)
        {
            return;
        }

        Levels[index].ClassName = className;
        Levels[index].Selections = [];
        if (className.Length == 0 || index == Levels.Count - 1)
        {
            return;
        }

        for (var futureIndex = index + 1; futureIndex < Levels.Count; futureIndex++)
        {
            var futureClass = Levels[futureIndex].ClassName;
            if (futureClass.Length > 0 && futureClass != replacedClass)
            {
                break;
            }

            if (futureClass != className)
            {
                Levels[futureIndex].ClassName = className;
                Levels[futureIndex].Selections = [];
            }
        }
    }

    [JsonIgnore]
    public string ClassSummary =>
        string.Join(
            " / ",
            Levels
                .Where(level => level.ClassName.Length > 0)
                .GroupBy(level => level.ClassName, StringComparer.Ordinal)
                .OrderBy(group => group.Key, StringComparer.Ordinal)
                .Select(group => $"{group.Key} {group.Count()}"));
}

public sealed record BuildOption(string Name, string Detail = "")
{
    [JsonIgnore]
    public string ArtworkFilename => $"{BuildArtwork.Slug(Name)}.webp";
}

public static partial class BuildArtwork
{
    [GeneratedRegex(@"[^\p{L}\p{Nd}]+")]
    private static partial Regex NonAlphanumeric();

    public static string Slug(string name)
    {
        var decomposed = name.Normalize(NormalizationForm.FormD);
        var withoutMarks = new string(
            decomposed
                .Where(
                    character =>
                        CharUnicodeInfo.GetUnicodeCategory(character) !=
                        UnicodeCategory.NonSpacingMark)
                .ToArray());
        return NonAlphanumeric()
            .Replace(withoutMarks.ToLowerInvariant(), "-")
            .Trim('-');
    }
}

public sealed record BuildChoiceGroup(
    string Id,
    string Title,
    int MaximumSelections,
    IReadOnlyList<BuildOption> Options,
    string? RequiredSelection = null,
    bool RequiresSelectionAtSameLevel = false);

public sealed record ClassLevelDefinition(
    IReadOnlyList<BuildOption> Features,
    IReadOnlyList<BuildChoiceGroup> Choices);

public sealed record ClassDefinition(
    string Name,
    IReadOnlyDictionary<int, ClassLevelDefinition> Levels);

public static class SpellCatalog
{
    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyDictionary<int, IReadOnlyList<string>>>>
        Catalog = new(Load);

    public static IReadOnlyDictionary<string, IReadOnlyDictionary<int, IReadOnlyList<string>>>
        ByClassAndRank => Catalog.Value;

    public static IReadOnlyList<string> Spells(
        string className,
        int through,
        int from = 0)
    {
        if (!Catalog.Value.TryGetValue(className, out var ranks))
        {
            return [];
        }

        return ranks
            .Where(entry => entry.Key >= from && entry.Key <= through)
            .OrderBy(entry => entry.Key)
            .SelectMany(entry => entry.Value)
            .ToArray();
    }

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<int, IReadOnlyList<string>>> Load()
    {
        const string resourceName =
            "BG3HonorAssistant.Core.Resources.spell-catalog.json";
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException(
                $"Embedded spell catalog '{resourceName}' was missing.");
        var payload = JsonSerializer.Deserialize<SpellCatalogPayload>(
            stream,
            new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
            }) ?? throw new InvalidOperationException("Embedded spell catalog was invalid.");
        return payload.Classes.ToDictionary(
            entry => entry.Key,
            entry => (IReadOnlyDictionary<int, IReadOnlyList<string>>)entry.Value
                .ToDictionary(
                    rank => rank.Key,
                    rank => (IReadOnlyList<string>)rank.Value),
            StringComparer.Ordinal);
    }

    private sealed record SpellCatalogPayload
    {
        [JsonPropertyName("classes")]
        public required Dictionary<string, Dictionary<int, string[]>> Classes { get; init; }
    }
}

public static class ClassCatalog
{
    private enum Spellcasting
    {
        None,
        Full,
        Prepared,
        Half,
    }

    private static readonly string[] Feats =
    [
        "Ability Improvement",
        "Actor",
        "Alert",
        "Athlete",
        "Charger",
        "Crossbow Expert",
        "Defensive Duellist",
        "Dual Wielder",
        "Dungeon Delver",
        "Durable",
        "Elemental Adept",
        "Great Weapon Master",
        "Heavily Armoured",
        "Heavy Armour Master",
        "Lightly Armoured",
        "Lucky",
        "Mage Slayer",
        "Magic Initiate: Bard",
        "Magic Initiate: Cleric",
        "Magic Initiate: Druid",
        "Magic Initiate: Sorcerer",
        "Magic Initiate: Warlock",
        "Magic Initiate: Wizard",
        "Martial Adept",
        "Medium Armour Master",
        "Mobile",
        "Moderately Armoured",
        "Performer",
        "Polearm Master",
        "Resilient",
        "Ritual Caster",
        "Savage Attacker",
        "Sentinel",
        "Sharpshooter",
        "Shield Master",
        "Skilled",
        "Spell Sniper",
        "Tavern Brawler",
        "Tough",
        "War Caster",
        "Weapon Master",
    ];

    private static readonly string[] CombatManoeuvres =
    [
        "Commander's Strike",
        "Disarming Attack",
        "Distracting Strike",
        "Evasive Footwork",
        "Feinting Attack",
        "Goading Attack",
        "Manoeuvring Attack",
        "Menacing Attack",
        "Precision Attack",
        "Pushing Attack",
        "Rally",
        "Riposte",
        "Sweeping Attack",
        "Trip Attack",
    ];

    private static readonly string[] AbilityNames =
        Enum.GetNames<Ability>();

    public static IReadOnlyList<ClassDefinition> Definitions { get; } =
    [
        CreateBarbarian(),
        Create(
            "Bard",
            3,
            ["College of Lore", "College of Valour", "College of Swords", "College of Glamour"],
            Spellcasting.Full),
        Create(
            "Cleric",
            1,
            [
                "Life Domain",
                "Light Domain",
                "Trickery Domain",
                "Knowledge Domain",
                "Nature Domain",
                "Tempest Domain",
                "War Domain",
                "Death Domain",
            ],
            Spellcasting.Prepared),
        Create(
            "Druid",
            2,
            ["Circle of the Land", "Circle of the Moon", "Circle of Spores", "Circle of the Stars"],
            Spellcasting.Prepared),
        CreateFighter(),
        Create(
            "Monk",
            3,
            [
                "Way of the Open Hand",
                "Way of Shadow",
                "Way of the Four Elements",
                "Way of the Drunken Master",
            ],
            Spellcasting.None),
        Create(
            "Paladin",
            1,
            [
                "Oath of the Ancients",
                "Oath of Devotion",
                "Oath of Vengeance",
                "Oathbreaker",
                "Oath of the Crown",
            ],
            Spellcasting.Half),
        CreateRanger(),
        Create(
            "Rogue",
            3,
            ["Thief", "Arcane Trickster", "Assassin", "Swashbuckler"],
            Spellcasting.None,
            extraFeatLevels: [10]),
        Create(
            "Sorcerer",
            1,
            ["Draconic Bloodline", "Wild Magic", "Storm Sorcery", "Shadow Magic"],
            Spellcasting.Full),
        Create(
            "Warlock",
            1,
            ["The Fiend", "The Great Old One", "The Archfey", "The Hexblade"],
            Spellcasting.Full),
        Create(
            "Wizard",
            2,
            [
                "Abjuration School",
                "Bladesinging",
                "Conjuration School",
                "Divination School",
                "Enchantment School",
                "Evocation School",
                "Illusion School",
                "Necromancy School",
                "Transmutation School",
            ],
            Spellcasting.Full),
    ];

    public static ClassDefinition? Definition(string name) =>
        Definitions.FirstOrDefault(definition => definition.Name == name);

    private static ClassDefinition CreateBarbarian()
    {
        var result = Create(
            "Barbarian",
            3,
            ["Berserker", "Wildheart", "Wild Magic", "Path of Giants"],
            Spellcasting.None);
        AddChoice(
            result,
            3,
            new BuildChoiceGroup(
                "bestial-heart",
                "Bestial Heart",
                1,
                Options(["Bear Heart", "Eagle Heart", "Elk Heart", "Tiger Heart", "Wolf Heart"]),
                "Wildheart"));
        return result;
    }

    private static ClassDefinition CreateFighter()
    {
        var result = Create(
            "Fighter",
            3,
            ["Battle Master", "Champion", "Eldritch Knight", "Arcane Archer"],
            Spellcasting.None,
            extraFeatLevels: [6]);
        AddChoice(
            result,
            3,
            new BuildChoiceGroup(
                "manoeuvres-3",
                "Battle Manoeuvres",
                3,
                Options(CombatManoeuvres),
                "Battle Master"));
        return result;
    }

    private static ClassDefinition CreateRanger()
    {
        var result = Create(
            "Ranger",
            3,
            ["Hunter", "Beast Master", "Gloom Stalker", "Swarmkeeper"],
            Spellcasting.Half);
        AddChoice(
            result,
            3,
            new BuildChoiceGroup(
                "hunters-prey",
                "Hunter's Prey",
                1,
                Options(["Colossus Slayer", "Giant Killer", "Horde Breaker"]),
                "Hunter"));
        return result;
    }

    private static ClassDefinition Create(
        string name,
        int subclassLevel,
        IReadOnlyList<string> subclasses,
        Spellcasting spellcasting,
        IReadOnlyList<int>? extraFeatLevels = null)
    {
        var levels = Enumerable.Range(1, 12)
            .ToDictionary(
                level => level,
                _ => new ClassLevelDefinition([], []));
        for (var level = 1; level <= 12; level++)
        {
            var choices = new List<BuildChoiceGroup>();
            if (level == subclassLevel)
            {
                choices.Add(
                    new BuildChoiceGroup(
                        "subclass",
                        "Subclass",
                        1,
                        Options(subclasses)));
            }

            if (level is 4 or 8 or 12 ||
                extraFeatLevels?.Contains(level) == true)
            {
                choices.AddRange(FeatChoiceGroups(level));
            }

            if (spellcasting != Spellcasting.None)
            {
                var rank = MaximumSpellRank(level, spellcasting);
                var count = SpellSelectionCount(name, level, spellcasting);
                if (count > 0)
                {
                    choices.Add(
                        new BuildChoiceGroup(
                            $"spells-{level}",
                            spellcasting == Spellcasting.Prepared
                                ? "Prepared Spells"
                                : "Learn Spells",
                            count,
                            Options(SpellCatalog.Spells(name, rank, 1))));
                }

                if (rank > 0 && level == 1)
                {
                    var cantrips = SpellCatalog.ByClassAndRank
                        .GetValueOrDefault(name)?
                        .GetValueOrDefault(0) ?? [];
                    choices.Add(
                        new BuildChoiceGroup(
                            "cantrips",
                            "Cantrips",
                            CantripCount(name),
                            Options(cantrips)));
                }
            }

            levels[level] = new ClassLevelDefinition([], choices);
        }

        return new ClassDefinition(name, levels);
    }

    private static IReadOnlyList<BuildChoiceGroup> FeatChoiceGroups(int level)
    {
        var result = new List<BuildChoiceGroup>
        {
            new($"feat-{level}", "Feat or Ability Improvement", 1, Options(Feats)),
            new(
                $"ability-improvement-{level}",
                "Ability Improvement Allocation",
                1,
                Options(AbilityImprovementOptions()),
                "Ability Improvement",
                true),
        };
        foreach (var className in new[] { "Bard", "Cleric", "Druid", "Sorcerer", "Warlock", "Wizard" })
        {
            var requirement = $"Magic Initiate: {className}";
            var cantrips = SpellCatalog.ByClassAndRank
                .GetValueOrDefault(className)?
                .GetValueOrDefault(0) ?? [];
            var spells = SpellCatalog.ByClassAndRank
                .GetValueOrDefault(className)?
                .GetValueOrDefault(1) ?? [];
            result.Add(
                new BuildChoiceGroup(
                    $"magic-initiate-{className.ToLowerInvariant()}-cantrips-{level}",
                    $"{requirement} Cantrips",
                    2,
                    Options(cantrips),
                    requirement,
                    true));
            result.Add(
                new BuildChoiceGroup(
                    $"magic-initiate-{className.ToLowerInvariant()}-spell-{level}",
                    $"{requirement} Spell",
                    1,
                    Options(spells),
                    requirement,
                    true));
        }

        return result;
    }

    private static IReadOnlyList<string> AbilityImprovementOptions()
    {
        var names = AbilityNames.Select(name => $"+2 {name}").ToList();
        for (var first = 0; first < AbilityNames.Length; first++)
        {
            for (var second = first + 1; second < AbilityNames.Length; second++)
            {
                names.Add($"+1 {AbilityNames[first]} / +1 {AbilityNames[second]}");
            }
        }

        return names;
    }

    private static int MaximumSpellRank(int classLevel, Spellcasting spellcasting) =>
        spellcasting switch
        {
            Spellcasting.None => 0,
            Spellcasting.Full or Spellcasting.Prepared => Math.Min(6, (classLevel + 1) / 2),
            Spellcasting.Half => classLevel < 2 ? 0 : Math.Min(3, (classLevel + 3) / 4),
            _ => throw new ArgumentOutOfRangeException(nameof(spellcasting)),
        };

    private static int SpellSelectionCount(
        string className,
        int classLevel,
        Spellcasting spellcasting)
    {
        if (spellcasting == Spellcasting.Prepared) return classLevel == 1 ? 4 : 2;
        if (className == "Warlock") return classLevel == 1
            ? 2
            : new[] { 2, 3, 4, 5, 7, 9 }.Contains(classLevel) ? 1 : 0;
        if (className == "Bard") return classLevel == 1 ? 4 : 1;
        if (className == "Sorcerer") return classLevel == 1 ? 2 : 1;
        if (spellcasting == Spellcasting.Half) return classLevel >= 2 ? 1 : 0;
        if (className == "Wizard") return classLevel == 1 ? 6 : 2;
        return 0;
    }

    private static int CantripCount(string className) =>
        className switch
        {
            "Bard" or "Cleric" or "Druid" or "Warlock" => 2,
            "Sorcerer" => 4,
            "Wizard" => 3,
            _ => 0,
        };

    private static IReadOnlyList<BuildOption> Options(
        IEnumerable<string> names) =>
        names.Select(name => new BuildOption(name)).ToArray();

    private static void AddChoice(
        ClassDefinition definition,
        int level,
        BuildChoiceGroup choice)
    {
        var current = definition.Levels[level];
        ((Dictionary<int, ClassLevelDefinition>)definition.Levels)[level] =
            current with
            {
                Choices = current.Choices.Concat([choice]).ToArray(),
            };
    }
}
