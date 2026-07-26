using System.Text.RegularExpressions;

namespace BG3HonorAssistant.Core.Models;

public sealed record BuildImportLevel(
    int Level,
    string Take,
    string SubclassChoice,
    string Choices,
    string Tactics,
    string Confidence,
    AbilityScores? AbilityScoreReset = null);

public sealed record BuildImportGear
{
    public required string Item { get; init; }

    public required string Slot { get; init; }

    public required string Priority { get; init; }

    public required int Act { get; init; }

    public required string Region { get; init; }

    public required string Acquisition { get; init; }

    public required string Why { get; init; }

    public int? MinimumLevel { get; init; }

    public int? MaximumLevel { get; init; }

    public string? Requirement { get; init; }

    public string? Alternative { get; init; }
}

public sealed record ImportedBuild(
    string Id,
    string Name,
    string SourceUrl,
    BuildSummary Build);

public sealed record BuildImportDraft
{
    private static readonly string[] ClassNames =
    [
        "barbarian",
        "bard",
        "cleric",
        "druid",
        "fighter",
        "monk",
        "paladin",
        "ranger",
        "rogue",
        "sorcerer",
        "warlock",
        "wizard",
    ];

    public required string Name { get; init; }

    public required string Role { get; init; }

    public required string FinalSplit { get; init; }

    public required string ClassProgression { get; init; }

    public required AbilityScores PointBuyScores { get; init; }

    public required Ability BonusTwo { get; init; }

    public required Ability BonusOne { get; init; }

    public required string PlayPattern { get; init; }

    public required string Caveat { get; init; }

    public required IReadOnlyList<BuildImportLevel> Levels { get; init; }

    public required IReadOnlyList<BuildImportGear> Gear { get; init; }

    public ImportedBuild Import(Uri sourceUri)
    {
        var issues = new List<string>();
        var finalSplitTotal = ClassLevelTotal(FinalSplit);
        var normalizedFinalSplit = finalSplitTotal == 12
            ? FinalSplit
            : FinalSplitDerived(Levels) ?? FinalSplit;

        if (string.IsNullOrWhiteSpace(Name))
        {
            issues.Add("The build name is empty.");
        }

        if (BonusTwo == BonusOne)
        {
            issues.Add("The +2 and +1 bonuses must use different abilities.");
        }

        if (AbilityProgression.PointBuyCost(PointBuyScores) != 27)
        {
            issues.Add("The base abilities are not a legal 27-point BG3 point buy.");
        }

        if (Levels.Any(level => level.Level is < 1 or > 12))
        {
            issues.Add("Character levels must be between 1 and 12.");
        }

        if (Levels.Select(level => level.Level).Distinct().Count() != Levels.Count)
        {
            issues.Add("Character levels contain duplicates.");
        }

        var finalTotal = ClassLevelTotal(normalizedFinalSplit);
        if (Levels.Select(level => level.Level).DefaultIfEmpty().Max() == 12 &&
            finalTotal != 12)
        {
            issues.Add($"The final class split totals {finalTotal}, not 12.");
        }

        if (issues.Count > 0)
        {
            throw new BuildImportException(issues);
        }

        var finalScores = PointBuyScores.Add(2, BonusTwo).Add(1, BonusOne);
        var slug = Regex.Replace(Name.ToLowerInvariant(), @"[^a-z0-9]+", "-").Trim('-');
        var id = $"imported-{(slug.Length == 0 ? Guid.NewGuid().ToString().ToLowerInvariant() : slug)}";
        var setup = new AbilitySetupPlan
        {
            Id = $"{id}-starting",
            Level = 1,
            Label = "Starting abilities",
            Reason = "Extracted from the imported public build guide.",
            PointBuyScores = PointBuyScores,
            BonusTwo = BonusTwo,
            BonusOne = BonusOne,
            FinalScores = finalScores,
            FirstClass = Levels.OrderBy(level => level.Level).FirstOrDefault()?.Take ?? FinalSplit,
            ClassOrder = ClassProgression,
        };
        var source = sourceUri.AbsoluteUri;
        var build = new BuildSummary
        {
            Id = id,
            Name = Name,
            HonorStatus = "Imported; verify choices in game",
            Role = Role,
            FinalSplit = normalizedFinalSplit,
            ClassProgression = ClassProgression,
            StartingAbilities = finalScores.Summary,
            StartingAbilityScores = finalScores,
            AbilitySetups = [setup],
            PlayPattern = PlayPattern,
            Caveat = Caveat,
            Source = source,
            Levels = Levels
                .OrderBy(level => level.Level)
                .Select(
                    level => new BuildLevel(
                        level.Level,
                        level.Take,
                        level.SubclassChoice,
                        level.Choices,
                        level.Tactics,
                        level.Confidence,
                        level.AbilityScoreReset))
                .ToArray(),
            Gear = Gear
                .Select(
                    gear => new BuildGear
                    {
                        Item = gear.Item,
                        Slot = gear.Slot,
                        Priority = gear.Priority,
                        Act = Math.Clamp(gear.Act, 1, 3),
                        Region = gear.Region,
                        Acquisition = gear.Acquisition,
                        Why = gear.Why,
                        Source = source,
                        MinimumLevel = gear.MinimumLevel,
                        MaximumLevel = gear.MaximumLevel,
                        Requirement = gear.Requirement,
                        Alternative = gear.Alternative,
                    })
                .ToArray(),
        };
        return new ImportedBuild(id, Name, source, build);
    }

    private static int ClassLevelTotal(string split) =>
        Regex.Matches(split, @"\d+")
            .Select(match => int.Parse(match.Value, System.Globalization.CultureInfo.InvariantCulture))
            .Sum();

    private static string? FinalSplitDerived(IReadOnlyList<BuildImportLevel> levels)
    {
        var maxima = new Dictionary<string, int>(StringComparer.Ordinal);
        var order = new List<string>();
        foreach (var level in levels.OrderBy(level => level.Level))
        {
            var lower = level.Take.ToLowerInvariant();
            var className = ClassNames.FirstOrDefault(
                candidate => Regex.IsMatch(lower, $@"\b{Regex.Escape(candidate)}\b"));
            var classLevels = Regex.Matches(level.Take, @"\d+")
                .Select(match => int.Parse(match.Value, System.Globalization.CultureInfo.InvariantCulture))
                .ToArray();
            if (className is null || classLevels.Length == 0)
            {
                continue;
            }

            if (!maxima.ContainsKey(className))
            {
                order.Add(className);
            }

            maxima[className] = Math.Max(maxima.GetValueOrDefault(className), classLevels[^1]);
        }

        if (maxima.Values.Sum() != 12)
        {
            return null;
        }

        return string.Join(
            " / ",
            order.Select(name => $"{char.ToUpperInvariant(name[0])}{name[1..]} {maxima[name]}"));
    }
}

public sealed class BuildImportException : Exception
{
    public BuildImportException(IReadOnlyList<string> issues)
        : base(string.Join(" ", issues))
    {
        Issues = issues;
    }

    public IReadOnlyList<string> Issues { get; }
}
