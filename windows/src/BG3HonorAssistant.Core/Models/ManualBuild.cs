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

    public bool ChoiceIsAvailable(
        BuildChoiceGroup group,
        ManualBuildLevel level)
    {
        if (group.RequiredSelection is not { } requirement)
        {
            return true;
        }

        return group.RequiresSelectionAtSameLevel
            ? level.Selections.Values.Any(
                selections => selections.Contains(requirement, StringComparer.Ordinal))
            : Levels.Any(
                candidate =>
                    candidate.Selections.Values.Any(
                        selections =>
                            selections.Contains(requirement, StringComparer.Ordinal)));
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

    private static readonly string[] Skills =
    [
        "Acrobatics",
        "Animal Handling",
        "Arcana",
        "Athletics",
        "Deception",
        "History",
        "Insight",
        "Intimidation",
        "Investigation",
        "Medicine",
        "Nature",
        "Perception",
        "Performance",
        "Persuasion",
        "Religion",
        "Sleight of Hand",
        "Stealth",
        "Survival",
    ];

    private static readonly string[] FightingStyles =
    [
        "Archery",
        "Defence",
        "Duelling",
        "Great Weapon Fighting",
        "Protection",
        "Two-Weapon Fighting",
    ];

    private static readonly string[] MagicalSecrets =
    [
        "Bone Chill", "Eldritch Blast", "Fire Bolt", "Ray of Frost", "Sacred Flame",
        "Armour of Agathys", "Bless", "Chromatic Orb", "Command", "Entangle", "False Life",
        "Guiding Bolt", "Hellish Rebuke", "Hex", "Hunter's Mark", "Ice Knife", "Magic Missile",
        "Sanctuary", "Thunderous Smite", "Arcane Lock", "Blur", "Darkness", "Darkvision",
        "Misty Step", "Pass Without Trace", "Ray of Enfeeblement", "Scorching Ray",
        "Spike Growth", "Spiritual Weapon", "Web", "Animate Dead", "Call Lightning",
        "Counterspell", "Crusader's Mantle", "Daylight", "Fireball", "Gaseous Form",
        "Grant Flight", "Haste", "Hunger of Hadar", "Lightning Bolt", "Mass Healing Word",
        "Remove Curse", "Revivify", "Sleet Storm", "Slow", "Spirit Guardians",
        "Vampiric Touch", "Warden of Vitality", "Banishment", "Blight", "Death Ward",
        "Dominate Beast", "Fire Shield", "Guardian of Faith", "Ice Storm", "Wall of Fire",
        "Banishing Smite", "Cone of Cold", "Conjure Elemental", "Contagion", "Wall of Stone",
    ];

    public static IReadOnlyList<ClassDefinition> Definitions { get; } =
    [
        CreateBarbarian(),
        CreateBard(),
        CreateCleric(),
        CreateDruid(),
        CreateFighter(),
        CreateMonk(),
        CreatePaladin(),
        CreateRanger(),
        CreateRogue(),
        CreateSorcerer(),
        CreateWarlock(),
        CreateWizard(),
    ];

    public static ClassDefinition? Definition(string name) =>
        Definitions.FirstOrDefault(definition => definition.Name == name);

    private static ClassDefinition CreateBarbarian()
    {
        var result = Create(
            "Barbarian",
            3,
            ["Berserker", "Wildheart", "Wild Magic", "Path of Giants"],
            Spellcasting.None,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Rage", "Unarmoured Defence"],
                [2] = ["Danger Sense", "Reckless Attack"],
                [3] = ["Additional Rage Charge"],
                [5] = ["Extra Attack", "Fast Movement"],
                [6] = ["Additional Rage Charge"],
                [7] = ["Feral Instinct"],
                [8] = ["Lands Stride: Difficult Terrain"],
                [9] = ["Brutal Critical"],
                [10] = ["Additional Rage Charge"],
                [11] = ["Relentless Rage"],
            });
        var hearts = Options(
            ["Bear Heart", "Eagle Heart", "Elk Heart", "Tiger Heart", "Wolf Heart"]);
        var aspects = Options(
            [
                "Bear", "Chimpanzee", "Crocodile", "Eagle", "Elk",
                "Honey Badger", "Stallion", "Tiger", "Wolf", "Wolverine",
            ]);
        AddChoice(
            result,
            3,
            new BuildChoiceGroup(
                "bestial-heart",
                "Bestial Heart",
                1,
                hearts,
                "Wildheart"));
        AddChoice(
            result,
            6,
            new BuildChoiceGroup(
                "animal-aspect-6",
                "Animal Aspect",
                1,
                aspects,
                "Wildheart"));
        AddChoice(
            result,
            10,
            new BuildChoiceGroup(
                "animal-aspect-10",
                "Additional Animal Aspect",
                1,
                aspects,
                "Wildheart"));
        AddChoice(
            result,
            6,
            new BuildChoiceGroup(
                "elemental-cleaver",
                "Elemental Cleaver",
                1,
                Options(["Acid", "Cold", "Fire", "Lightning", "Thunder"]),
                "Path of Giants"));
        return result;
    }

    private static ClassDefinition CreateBard()
    {
        var result = Create(
            "Bard",
            3,
            ["College of Lore", "College of Valour", "College of Swords", "College of Glamour"],
            Spellcasting.Full,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Bardic Inspiration"],
                [2] = ["Jack of All Trades", "Song of Rest"],
                [3] = ["Expertise"],
                [5] = ["Font of Inspiration", "Improved Bardic Inspiration"],
                [6] = ["Countercharm"],
                [10] = ["Expertise", "Magical Secrets"],
            });
        AddChoice(result, 3, Choice("expertise-3", "Expertise", 2, Skills));
        AddChoice(result, 10, Choice("expertise-10", "Expertise", 2, Skills));
        AddChoice(
            result,
            3,
            Choice(
                "lore-skills",
                "College of Lore Skills",
                3,
                Skills,
                "College of Lore"));
        AddChoice(
            result,
            3,
            Choice(
                "swords-style",
                "College of Swords Fighting Style",
                1,
                ["Duelling", "Two-Weapon Fighting"],
                "College of Swords"));
        AddChoice(
            result,
            6,
            Choice(
                "lore-magical-secrets",
                "Magical Secrets",
                2,
                MagicalSecrets,
                "College of Lore"));
        AddChoice(
            result,
            10,
            Choice("magical-secrets", "Magical Secrets", 2, MagicalSecrets));
        return result;
    }

    private static ClassDefinition CreateCleric()
    {
        var result = Create(
            "Cleric",
            1,
            [
                "Life Domain", "Light Domain", "Trickery Domain", "Knowledge Domain",
                "Nature Domain", "Tempest Domain", "War Domain", "Death Domain",
            ],
            Spellcasting.Prepared,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Channel Divinity"],
                [2] = ["Turn Undead"],
                [5] = ["Destroy Undead"],
                [10] = ["Divine Intervention"],
            });
        AddChoice(
            result,
            10,
            Choice(
                "divine-intervention",
                "Divine Intervention",
                1,
                [
                    "Arm Thy Servant", "Golden Generosity",
                    "Opulent Revival", "Sunder the Heretical",
                ]));
        return result;
    }

    private static ClassDefinition CreateDruid()
    {
        var result = Create(
            "Druid",
            2,
            ["Circle of the Land", "Circle of the Moon", "Circle of Spores", "Circle of the Stars"],
            Spellcasting.Prepared,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Druidic"],
                [2] = ["Wild Shape"],
                [4] = ["Wild Shape: Deep Rothé"],
                [5] = ["Wild Strike"],
                [8] = ["Wild Shape: Sabre-Toothed Tiger"],
                [10] = ["Improved Wild Strike"],
            });
        var lands = new[]
        {
            "Arctic", "Coast", "Desert", "Forest",
            "Grassland", "Mountain", "Swamp", "Underdark",
        };
        foreach (var level in new[] { 3, 5, 7, 9 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"land-{level}",
                    "Circle Spells Land",
                    1,
                    lands,
                    "Circle of the Land"));
        }

        return result;
    }

    private static ClassDefinition CreateFighter()
    {
        var result = Create(
            "Fighter",
            3,
            ["Battle Master", "Champion", "Eldritch Knight", "Arcane Archer"],
            Spellcasting.None,
            extraFeatLevels: [6],
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Second Wind"],
                [2] = ["Action Surge"],
                [5] = ["Extra Attack"],
                [9] = ["Indomitable"],
                [11] = ["Improved Extra Attack"],
            });
        AddChoice(
            result,
            1,
            Choice("fighting-style", "Fighting Style", 1, FightingStyles));
        AddChoice(
            result,
            3,
            Choice(
                "manoeuvres-3",
                "Battle Manoeuvres",
                3,
                CombatManoeuvres,
                "Battle Master"));
        foreach (var level in new[] { 7, 10 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"manoeuvres-{level}",
                    "Additional Battle Manoeuvres",
                    2,
                    CombatManoeuvres,
                    "Battle Master"));
        }

        var arcaneShots = new[]
        {
            "Banishing Arrow", "Beguiling Arrow", "Bursting Arrow", "Enfeebling Arrow",
            "Grasping Arrow", "Piercing Arrow", "Seeking Arrow", "Shadow Arrow",
        };
        AddChoice(
            result,
            3,
            Choice(
                "arcane-archer-cantrip",
                "Arcane Archer Cantrip",
                1,
                ["Guidance", "Light", "True Strike"],
                "Arcane Archer"));
        AddChoice(
            result,
            3,
            Choice(
                "arcane-shots-3",
                "Arcane Shots",
                3,
                arcaneShots,
                "Arcane Archer"));
        foreach (var level in new[] { 7, 10 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"arcane-shots-{level}",
                    "Additional Arcane Shot",
                    1,
                    arcaneShots,
                    "Arcane Archer"));
        }

        AddChoice(
            result,
            3,
            Choice(
                "eldritch-knight-cantrips",
                "Eldritch Knight Cantrips",
                2,
                SpellCatalog.ByClassAndRank["Wizard"][0],
                "Eldritch Knight"));
        AddChoice(
            result,
            3,
            Choice(
                "eldritch-knight-spells",
                "Eldritch Knight Spells",
                3,
                SpellCatalog.Spells("Wizard", 1, 1),
                "Eldritch Knight"));
        foreach (var level in new[] { 4, 7, 8, 10, 11 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"eldritch-knight-spell-{level}",
                    "Additional Eldritch Knight Spell",
                    1,
                    SpellCatalog.Spells("Wizard", level >= 7 ? 2 : 1, 1),
                    "Eldritch Knight"));
        }

        return result;
    }

    private static ClassDefinition CreateMonk()
    {
        var result = Create(
            "Monk",
            3,
            [
                "Way of the Open Hand", "Way of Shadow",
                "Way of the Four Elements", "Way of the Drunken Master",
            ],
            Spellcasting.None,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Martial Arts", "Unarmoured Defence", "Flurry of Blows"],
                [2] = ["Patient Defence", "Step of the Wind", "Unarmoured Movement"],
                [3] = ["Deflect Missiles"],
                [4] = ["Slow Fall"],
                [5] = ["Extra Attack", "Stunning Strike"],
                [6] = ["Ki-Empowered Strikes"],
                [7] = ["Evasion", "Stillness of Mind"],
                [9] = ["Advanced Unarmoured Movement"],
                [10] = ["Purity of Body"],
            });
        var disciplines = new[]
        {
            "Blade of Rime", "Chill of the Mountain", "Fangs of the Fire Snake",
            "Fist of Four Thunders", "Fist of Unbroken Air", "Rush of the Gale Spirits",
            "Shaping of the Ice", "Sphere of Elemental Balance", "Sweeping Cinder Strike",
            "Touch of the Storm", "Water Whip", "Clench of the North Wind",
            "Embrace of the Inferno", "Gong of the Summit", "Flames of the Phoenix",
            "Mist Stance", "Ride the Wind",
        };
        AddChoice(
            result,
            3,
            Choice(
                "disciplines-3",
                "Elemental Disciplines",
                3,
                disciplines,
                "Way of the Four Elements"));
        foreach (var level in new[] { 6, 9, 11 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"disciplines-{level}",
                    "Additional Elemental Discipline",
                    1,
                    disciplines,
                    "Way of the Four Elements"));
        }

        return result;
    }

    private static ClassDefinition CreatePaladin()
    {
        var result = Create(
            "Paladin",
            1,
            [
                "Oath of the Ancients", "Oath of Devotion", "Oath of Vengeance",
                "Oathbreaker", "Oath of the Crown",
            ],
            Spellcasting.Half,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Lay on Hands", "Channel Oath Charges"],
                [2] = ["Divine Smite"],
                [3] = ["Divine Health"],
                [5] = ["Extra Attack"],
                [6] = ["Aura of Protection"],
                [9] = ["Additional Channel Oath Charge"],
                [10] = ["Aura of Courage"],
                [11] = ["Improved Divine Smite"],
            });
        AddChoice(
            result,
            2,
            Choice("fighting-style", "Fighting Style", 1, FightingStyles));
        return result;
    }

    private static ClassDefinition CreateRanger()
    {
        var result = Create(
            "Ranger",
            3,
            ["Hunter", "Beast Master", "Gloom Stalker", "Swarmkeeper"],
            Spellcasting.Half,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Favoured Enemy", "Natural Explorer"],
                [3] = ["Primeval Awareness"],
                [5] = ["Extra Attack"],
                [6] = ["Favoured Enemy", "Natural Explorer"],
                [8] = ["Land's Stride: Difficult Terrain"],
                [10] = ["Hide in Plain Sight", "Favoured Enemy", "Natural Explorer"],
            });
        AddChoice(
            result,
            2,
            Choice("fighting-style", "Fighting Style", 1, FightingStyles));
        var favouredEnemies = new[]
        {
            "Bounty Hunter", "Keeper of the Veil", "Mage Breaker",
            "Ranger Knight", "Sanctified Stalker",
        };
        var naturalExplorers = new[]
        {
            "Beast Tamer", "Urban Tracker", "Wasteland Wanderer: Cold",
            "Wasteland Wanderer: Fire", "Wasteland Wanderer: Poison",
        };
        AddChoice(
            result,
            1,
            Choice("favoured-enemy", "Favoured Enemy", 1, favouredEnemies));
        AddChoice(
            result,
            1,
            Choice("natural-explorer", "Natural Explorer", 1, naturalExplorers));
        foreach (var level in new[] { 6, 10 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"favoured-enemy-{level}",
                    "Favoured Enemy",
                    1,
                    favouredEnemies));
            AddChoice(
                result,
                level,
                Choice(
                    $"natural-explorer-{level}",
                    "Natural Explorer",
                    1,
                    naturalExplorers));
        }

        AddChoice(
            result,
            3,
            Choice(
                "hunters-prey",
                "Hunter's Prey",
                1,
                ["Colossus Slayer", "Giant Killer", "Horde Breaker"],
                "Hunter"));
        AddChoice(
            result,
            7,
            Choice(
                "defensive-tactics",
                "Defensive Tactics",
                1,
                ["Escape the Horde", "Steel Will", "Multiattack Defence"],
                "Hunter"));
        AddChoice(
            result,
            3,
            Choice(
                "beast-companion",
                "Primary Beast Companion",
                1,
                ["Bear", "Boar", "Dire Raven", "Wolf", "Wolf Spider"],
                "Beast Master"));
        AddChoice(
            result,
            3,
            Choice(
                "swarm",
                "Gathered Swarm",
                1,
                ["Cloud of Jellyfish", "Flurry of Moths", "Legion of Bees"],
                "Swarmkeeper"));
        return result;
    }

    private static ClassDefinition CreateRogue()
    {
        var result = Create(
            "Rogue",
            3,
            ["Thief", "Arcane Trickster", "Assassin", "Swashbuckler"],
            Spellcasting.None,
            extraFeatLevels: [10],
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Sneak Attack", "Expertise"],
                [2] = ["Cunning Action"],
                [5] = ["Uncanny Dodge"],
                [6] = ["Expertise"],
                [7] = ["Evasion"],
                [11] = ["Reliable Talent"],
            });
        AddChoice(result, 1, Choice("expertise-1", "Expertise", 2, Skills));
        AddChoice(result, 6, Choice("expertise-6", "Expertise", 2, Skills));
        AddChoice(
            result,
            3,
            Choice(
                "arcane-trickster-cantrips",
                "Arcane Trickster Cantrips",
                2,
                SpellCatalog.ByClassAndRank["Wizard"][0],
                "Arcane Trickster"));
        AddChoice(
            result,
            3,
            Choice(
                "arcane-trickster-spells",
                "Arcane Trickster Spells",
                3,
                SpellCatalog.Spells("Wizard", 1, 1),
                "Arcane Trickster"));
        foreach (var level in new[] { 4, 7, 8, 10, 11 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"arcane-trickster-spell-{level}",
                    "Additional Arcane Trickster Spell",
                    1,
                    SpellCatalog.Spells("Wizard", level >= 7 ? 2 : 1, 1),
                    "Arcane Trickster"));
        }

        return result;
    }

    private static ClassDefinition CreateSorcerer()
    {
        var result = Create(
            "Sorcerer",
            1,
            ["Draconic Bloodline", "Wild Magic", "Storm Sorcery", "Shadow Magic"],
            Spellcasting.Full,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Sorcery Points"],
                [2] = ["Create Spell Slot", "Create Sorcery Points"],
                [3] = ["Metamagic"],
                [10] = ["Metamagic"],
            });
        var metamagic = new[]
        {
            "Careful Spell", "Distant Spell", "Extended Spell", "Twinned Spell",
            "Heightened Spell", "Quickened Spell", "Subtle Spell",
        };
        AddChoice(result, 2, Choice("metamagic-2", "Metamagic", 2, metamagic));
        AddChoice(
            result,
            3,
            Choice("metamagic-3", "Additional Metamagic", 1, metamagic));
        AddChoice(
            result,
            10,
            Choice("metamagic-10", "Additional Metamagic", 1, metamagic));
        AddChoice(
            result,
            1,
            Choice(
                "draconic-ancestry",
                "Draconic Ancestry",
                1,
                [
                    "Red (Fire)", "Black (Acid)", "Blue (Lightning)", "White (Cold)",
                    "Green (Poison)", "Gold (Fire)", "Silver (Cold)", "Bronze (Lightning)",
                    "Copper (Acid)", "Brass (Fire)",
                ],
                "Draconic Bloodline"));
        return result;
    }

    private static ClassDefinition CreateWarlock()
    {
        var result = Create(
            "Warlock",
            1,
            ["The Fiend", "The Great Old One", "The Archfey", "The Hexblade"],
            Spellcasting.Full,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Pact Magic"],
                [2] = ["Eldritch Invocations"],
                [3] = ["Pact Boon"],
                [5] = ["Deepened Pact"],
                [11] = ["Mystic Arcanum"],
            });
        var invocations = new[]
        {
            "Agonising Blast", "Armour of Shadows", "Beast Speech", "Beguiling Influence",
            "Devil's Sight", "Fiendish Vigour", "Mask of Many Faces", "One with Shadows",
            "Repelling Blast", "Thief of Five Fates", "Book of Ancient Secrets", "Dreadful Word",
            "Minions of Chaos", "Mire the Mind", "Otherworldly Leap", "Sculptor of Flesh",
            "Sign of Ill Omen", "Whispers of the Grave", "Lifedrinker",
        };
        AddChoice(
            result,
            2,
            Choice("invocations-2", "Eldritch Invocations", 2, invocations));
        foreach (var level in new[] { 5, 7, 9, 12 })
        {
            AddChoice(
                result,
                level,
                Choice(
                    $"invocations-{level}",
                    "Additional Invocation",
                    1,
                    invocations));
        }

        AddChoice(
            result,
            3,
            Choice(
                "pact-boon",
                "Pact Boon",
                1,
                ["Pact of the Blade", "Pact of the Chain", "Pact of the Tome"]));
        AddChoice(
            result,
            11,
            Choice(
                "mystic-arcanum",
                "Mystic Arcanum",
                1,
                SpellCatalog.ByClassAndRank["Warlock"][6]));
        return result;
    }

    private static ClassDefinition CreateWizard() =>
        Create(
            "Wizard",
            2,
            [
                "Abjuration School", "Bladesinging", "Conjuration School",
                "Divination School", "Enchantment School", "Evocation School",
                "Illusion School", "Necromancy School", "Transmutation School",
            ],
            Spellcasting.Full,
            features: new Dictionary<int, IReadOnlyList<string>>
            {
                [1] = ["Arcane Recovery", "Spellbook", "Scroll Transcription"],
            });

    private static ClassDefinition Create(
        string name,
        int subclassLevel,
        IReadOnlyList<string> subclasses,
        Spellcasting spellcasting,
        IReadOnlyList<int>? extraFeatLevels = null,
        IReadOnlyDictionary<int, IReadOnlyList<string>>? features = null)
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

            levels[level] = new ClassLevelDefinition(
                Options(features?.GetValueOrDefault(level) ?? []),
                choices);
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
            Choice(
                $"athlete-ability-{level}",
                "Athlete Ability",
                1,
                ["Strength", "Dexterity"],
                "Athlete",
                true),
            Choice(
                $"elemental-adept-{level}",
                "Elemental Adept Damage",
                1,
                ["Acid", "Cold", "Fire", "Lightning", "Thunder"],
                "Elemental Adept",
                true),
            Choice(
                $"moderately-armoured-{level}",
                "Moderately Armoured Ability",
                1,
                ["Strength", "Dexterity"],
                "Moderately Armoured",
                true),
            Choice(
                $"resilient-{level}",
                "Resilient Ability",
                1,
                AbilityNames,
                "Resilient",
                true),
            Choice(
                $"skilled-{level}",
                "Skilled Proficiencies",
                3,
                Skills,
                "Skilled",
                true),
            Choice(
                $"tavern-brawler-{level}",
                "Tavern Brawler Ability",
                1,
                ["Strength", "Constitution"],
                "Tavern Brawler",
                true),
            Choice(
                $"martial-adept-{level}",
                "Martial Adept Manoeuvres",
                2,
                CombatManoeuvres,
                "Martial Adept",
                true),
            Choice(
                $"ritual-caster-{level}",
                "Ritual Caster Spells",
                2,
                [
                    "Disguise Self", "Enhance Leap", "Find Familiar",
                    "Longstrider", "Speak with Animals", "Speak with Dead",
                ],
                "Ritual Caster",
                true),
            Choice(
                $"spell-sniper-{level}",
                "Spell Sniper Cantrip",
                1,
                [
                    "Bone Chill", "Eldritch Blast", "Fire Bolt",
                    "Ray of Frost", "Shocking Grasp", "Thorn Whip",
                ],
                "Spell Sniper",
                true),
            Choice(
                $"weapon-master-ability-{level}",
                "Weapon Master Ability",
                1,
                ["Strength", "Dexterity"],
                "Weapon Master",
                true),
            Choice(
                $"weapon-master-proficiencies-{level}",
                "Weapon Master Proficiencies",
                4,
                [
                    "Battleaxes", "Clubs", "Daggers", "Darts", "Flails", "Glaives",
                    "Greataxes", "Greatclubs", "Greatswords", "Halberds", "Hand Crossbows",
                    "Handaxes", "Heavy Crossbows", "Javelins", "Light Crossbows",
                    "Light Hammers", "Longbows", "Longswords", "Maces", "Mauls",
                    "Morningstars", "Pikes", "Quarterstaves", "Rapiers", "Scimitars",
                    "Shortbows", "Shortswords", "Sickles", "Slings", "Spears",
                    "Tridents", "War Picks", "Warhammers",
                ],
                "Weapon Master",
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

    private static BuildChoiceGroup Choice(
        string id,
        string title,
        int maximumSelections,
        IEnumerable<string> options,
        string? requiredSelection = null,
        bool requiresSelectionAtSameLevel = false) =>
        new(
            id,
            title,
            maximumSelections,
            Options(options),
            requiredSelection,
            requiresSelectionAtSameLevel);

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
