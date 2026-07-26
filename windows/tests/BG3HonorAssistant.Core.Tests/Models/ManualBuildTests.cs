using BG3HonorAssistant.Core.Models;

namespace BG3HonorAssistant.Core.Tests.Models;

public sealed class ManualBuildTests
{
    [Fact]
    public void CatalogCoversEveryClassThroughLevelTwelve()
    {
        Assert.Equal(12, ClassCatalog.Definitions.Count);
        foreach (var definition in ClassCatalog.Definitions)
        {
            Assert.Equal(
                Enumerable.Range(1, 12).ToHashSet(),
                definition.Levels.Keys.ToHashSet());
        }
    }

    [Fact]
    public void WizardSeparatesCantripsFromLevelledSpells()
    {
        var wizard = RequireDefinition("Wizard");
        var level = wizard.Levels[1];
        var cantrips = Assert.Single(level.Choices, choice => choice.Id == "cantrips");
        var spells = Assert.Single(level.Choices, choice => choice.Id == "spells-1");

        Assert.Equal(3, cantrips.MaximumSelections);
        Assert.Equal(6, spells.MaximumSelections);
        Assert.Contains(cantrips.Options, option => option.Name == "Acid Splash");
        Assert.DoesNotContain(spells.Options, option => option.Name == "Acid Splash");
        Assert.Contains(spells.Options, option => option.Name == "Magic Missile");
        Assert.Contains(spells.Options, option => option.Name == "Shield");
    }

    [Fact]
    public void PatchEightSubclassesNeededByTankBuildAreAvailable()
    {
        var warlock = RequireDefinition("Warlock");
        var warlockSubclasses = Assert.Single(
            warlock.Levels[1].Choices,
            choice => choice.Id == "subclass");
        Assert.Contains(
            warlockSubclasses.Options,
            option => option.Name == "The Hexblade");

        var wizard = RequireDefinition("Wizard");
        var wizardSubclasses = Assert.Single(
            wizard.Levels[2].Choices,
            choice => choice.Id == "subclass");
        Assert.Contains(
            wizardSubclasses.Options,
            option => option.Name == "Abjuration School");
    }

    [Fact]
    public void SubclassSpecificChoicesAreCompleteAndConditional()
    {
        var fighter = RequireDefinition("Fighter");
        var manoeuvres = Assert.Single(
            fighter.Levels[3].Choices,
            choice => choice.Id == "manoeuvres-3");
        Assert.Equal("Battle Master", manoeuvres.RequiredSelection);
        Assert.Equal(3, manoeuvres.MaximumSelections);
        Assert.Contains(manoeuvres.Options, option => option.Name == "Riposte");
        Assert.Contains(manoeuvres.Options, option => option.Name == "Trip Attack");

        var ranger = RequireDefinition("Ranger");
        var hunter = Assert.Single(
            ranger.Levels[3].Choices,
            choice => choice.Id == "hunters-prey");
        Assert.Equal("Hunter", hunter.RequiredSelection);
        Assert.Equal(
            new[] { "Colossus Slayer", "Giant Killer", "Horde Breaker" }.ToHashSet(),
            hunter.Options.Select(option => option.Name).ToHashSet());

        var barbarian = RequireDefinition("Barbarian");
        var heart = Assert.Single(
            barbarian.Levels[3].Choices,
            choice => choice.Id == "bestial-heart");
        Assert.Equal("Wildheart", heart.RequiredSelection);
        Assert.Equal(5, heart.Options.Count);
    }

    [Fact]
    public void AbilityImprovementRecordsItsAllocationAtTheSameLevel()
    {
        var wizard = RequireDefinition("Wizard");
        var allocation = Assert.Single(
            wizard.Levels[4].Choices,
            choice => choice.Id == "ability-improvement-4");

        Assert.Equal("Ability Improvement", allocation.RequiredSelection);
        Assert.True(allocation.RequiresSelectionAtSameLevel);
        Assert.Contains(
            allocation.Options,
            option => option.Name == "+2 Intelligence");
        Assert.Contains(
            allocation.Options,
            option => option.Name == "+1 Constitution / +1 Intelligence");

        var initiate = Assert.Single(
            wizard.Levels[4].Choices,
            choice => choice.Id == "magic-initiate-warlock-spell-4");
        Assert.Equal("Magic Initiate: Warlock", initiate.RequiredSelection);
        Assert.True(initiate.RequiresSelectionAtSameLevel);
        Assert.Contains(
            initiate.Options,
            option => option.Name == "Armour of Agathys");
    }

    [Fact]
    public void FeatsExposeEveryLiveMacConditionalChoice()
    {
        var wizard = RequireDefinition("Wizard");
        var groups = wizard.Levels[4].Choices.ToDictionary(
            group => group.Id,
            StringComparer.Ordinal);
        var expected = new Dictionary<string, (int Maximum, string Requirement)>
        {
            ["ability-improvement-4"] = (1, "Ability Improvement"),
            ["athlete-ability-4"] = (1, "Athlete"),
            ["elemental-adept-4"] = (1, "Elemental Adept"),
            ["moderately-armoured-4"] = (1, "Moderately Armoured"),
            ["resilient-4"] = (1, "Resilient"),
            ["skilled-4"] = (3, "Skilled"),
            ["tavern-brawler-4"] = (1, "Tavern Brawler"),
            ["martial-adept-4"] = (2, "Martial Adept"),
            ["ritual-caster-4"] = (2, "Ritual Caster"),
            ["spell-sniper-4"] = (1, "Spell Sniper"),
            ["weapon-master-ability-4"] = (1, "Weapon Master"),
            ["weapon-master-proficiencies-4"] = (4, "Weapon Master"),
        };

        Assert.All(
            expected,
            pair =>
            {
                var group = groups[pair.Key];
                Assert.Equal(pair.Value.Maximum, group.MaximumSelections);
                Assert.Equal(pair.Value.Requirement, group.RequiredSelection);
                Assert.True(group.RequiresSelectionAtSameLevel);
                Assert.NotEmpty(group.Options);
            });
    }

    [Fact]
    public void ConditionalChoicesRequireTheReviewedSelectionScope()
    {
        var plan = ManualBuildPlan.Empty("Conditional", AbilityScores.CustomDefault);
        plan.SetClass("Wizard", 1);
        var level = plan.Levels[3];
        var definition = RequireDefinition("Wizard").Levels[4];
        var allocation = Assert.Single(
            definition.Choices,
            group => group.Id == "ability-improvement-4");

        Assert.False(plan.ChoiceIsAvailable(allocation, level));

        level.Selections["feat-4"] = ["Ability Improvement"];

        Assert.True(plan.ChoiceIsAvailable(allocation, level));
        var futureLevel = plan.Levels[7];
        Assert.False(plan.ChoiceIsAvailable(allocation, futureLevel));
    }

    [Fact]
    public void EveryClassKeepsItsLiveMacFeaturesAndSpecialChoices()
    {
        Assert.Contains(
            RequireDefinition("Barbarian").Levels[6].Features,
            option => option.Name == "Additional Rage Charge");
        RequireChoice("Barbarian", 10, "animal-aspect-10", "Wildheart");

        RequireChoice("Bard", 6, "lore-magical-secrets", "College of Lore");
        RequireChoice("Cleric", 10, "divine-intervention");
        RequireChoice("Druid", 9, "land-9", "Circle of the Land");
        RequireChoice("Fighter", 10, "arcane-shots-10", "Arcane Archer");
        RequireChoice("Fighter", 11, "eldritch-knight-spell-11", "Eldritch Knight");
        RequireChoice("Monk", 11, "disciplines-11", "Way of the Four Elements");
        RequireChoice("Paladin", 2, "fighting-style");
        RequireChoice("Ranger", 10, "natural-explorer-10");
        RequireChoice("Ranger", 3, "swarm", "Swarmkeeper");
        RequireChoice("Rogue", 11, "arcane-trickster-spell-11", "Arcane Trickster");
        RequireChoice("Sorcerer", 1, "draconic-ancestry", "Draconic Bloodline");
        RequireChoice("Warlock", 11, "mystic-arcanum");
        Assert.Contains(
            RequireDefinition("Wizard").Levels[1].Features,
            option => option.Name == "Scroll Transcription");
    }

    [Fact]
    public void TankBuildSpellsAreInCurrentClassLists()
    {
        Assert.Contains("Armour of Agathys", SpellCatalog.Spells("Warlock", 1));

        var wizard = SpellCatalog.Spells("Wizard", 6);
        foreach (var spell in new[]
                 {
                     "Magic Missile",
                     "Counterspell",
                     "Glyph of Warding",
                     "Fire Shield",
                     "Hold Monster",
                 })
        {
            Assert.Contains(spell, wizard);
        }
    }

    [Fact]
    public void ManualMulticlassLevelsAreCountedPerClass()
    {
        var plan = ManualBuildPlan.Empty(
            "Immortal Tank",
            AbilityScores.CustomDefault.ClampedForPointBuy);
        plan.Levels[0].ClassName = "Warlock";
        foreach (var level in plan.Levels.Skip(1))
        {
            level.ClassName = "Wizard";
        }

        Assert.Equal(1, plan.ClassLevel(1));
        Assert.Equal(1, plan.ClassLevel(2));
        Assert.Equal(2, plan.ClassLevel(3));
        Assert.Equal(11, plan.ClassLevel(12));
        Assert.Equal("Warlock 1 / Wizard 11", plan.ClassSummary);
    }

    [Fact]
    public void ClassChoiceContinuesUntilAnExplicitMulticlassBreak()
    {
        var plan = ManualBuildPlan.Empty(
            "Tank",
            AbilityScores.CustomDefault.ClampedForPointBuy);

        plan.SetClass("Warlock", 1);
        Assert.Equal(
            Enumerable.Repeat("Warlock", 12),
            plan.Levels.Select(level => level.ClassName));

        plan.SetClass("Wizard", 2);
        Assert.Equal("Warlock", plan.Levels[0].ClassName);
        Assert.Equal(
            Enumerable.Repeat("Wizard", 11),
            plan.Levels.Skip(1).Select(level => level.ClassName));

        plan.SetClass("Fighter", 10);
        plan.SetClass("Sorcerer", 5);
        Assert.Equal(
            Enumerable.Repeat("Sorcerer", 5),
            plan.Levels.Skip(4).Take(5).Select(level => level.ClassName));
        Assert.Equal(
            Enumerable.Repeat("Fighter", 3),
            plan.Levels.Skip(9).Take(3).Select(level => level.ClassName));
    }

    [Fact]
    public void EveryCatalogChoiceHasAStableArtworkFilename()
    {
        var options = AllOptions();

        Assert.True(options.Count > 1000, $"Only {options.Count} catalog entries were generated.");
        Assert.All(
            options,
            option =>
            {
                Assert.NotEmpty(option.ArtworkFilename);
                Assert.EndsWith(".webp", option.ArtworkFilename);
            });
        Assert.Equal("hunter-s-mark", BuildArtwork.Slug("Hunter's Mark"));
        Assert.Equal(
            "magic-initiate-warlock",
            BuildArtwork.Slug("Magic Initiate: Warlock"));
    }

    [Fact]
    public void EveryCatalogChoiceHasBundledArtwork()
    {
        var iconDirectory = FindBuildArtworkDirectory(AppContext.BaseDirectory);
        var missing = AllOptions()
            .Select(option => option.ArtworkFilename)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(filename => !File.Exists(Path.Combine(iconDirectory, filename)))
            .OrderBy(filename => filename, StringComparer.Ordinal)
            .ToArray();

        Assert.True(
            missing.Length == 0,
            $"Missing build artwork: {string.Join(", ", missing)}");
    }

    [Fact]
    public void LegacyRunsReceiveBalancedDifficultyAndFullRoute()
    {
        var run = new HonorRun
        {
            Difficulty = null,
            RouteRevealPolicy = null,
        };

        run.NormalizeRoster();

        Assert.Equal(RunDifficulty.Balanced, run.Difficulty);
        Assert.Equal(RouteRevealPolicy.Everything, run.RouteRevealPolicy);
    }

    private static IReadOnlyList<BuildOption> AllOptions() =>
        ClassCatalog.Definitions
            .SelectMany(definition => definition.Levels.Values)
            .SelectMany(
                level => level.Features.Concat(
                    level.Choices.SelectMany(choice => choice.Options)))
            .ToArray();

    private static ClassDefinition RequireDefinition(string name)
    {
        var definition = ClassCatalog.Definition(name);
        Assert.NotNull(definition);
        return definition!;
    }

    private static BuildChoiceGroup RequireChoice(
        string className,
        int level,
        string id,
        string? requiredSelection = null)
    {
        var choice = Assert.Single(
            RequireDefinition(className).Levels[level].Choices,
            group => group.Id == id);
        Assert.Equal(requiredSelection, choice.RequiredSelection);
        Assert.NotEmpty(choice.Options);
        return choice;
    }

    [Fact]
    public void BuildArtworkLookupDoesNotDependOnAWindowsOutputDepth()
    {
        var artwork = FindBuildArtworkDirectory(
            Path.Combine(
                AppContext.BaseDirectory,
                "architecture",
                "configuration",
                "framework",
                "rid",
                "publish"));

        Assert.Equal("BuildOptionIcons", Path.GetFileName(artwork));
    }

    private static string FindBuildArtworkDirectory(string startPath)
    {
        var directory = new DirectoryInfo(startPath);
        while (directory is not null)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "Resources",
                "BuildOptionIcons");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException(
            "Could not locate the shared build artwork directory.");
    }
}
