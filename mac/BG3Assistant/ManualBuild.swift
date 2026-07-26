import AppKit
import Foundation
import SwiftUI

enum RunDifficulty: String, Codable, CaseIterable, Identifiable {
    case explorer
    case balanced
    case tactician
    case honour
    case custom

    var id: String { rawValue }

    /// Custom remains decodable for existing runs, but is not offered because
    /// its rule combinations cannot be modeled reliably.
    static let selectableOverlayDifficulties: [RunDifficulty] = [.balanced, .tactician, .honour]

    var supportsOverlay: Bool {
        switch self {
        case .balanced, .tactician, .honour, .custom: true
        case .explorer: false
        }
    }

    var title: String {
        switch self {
        case .explorer: "Explorer"
        case .balanced: "Balanced"
        case .tactician: "Tactician"
        case .honour: "Honour Mode"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .explorer: "Explorer is best enjoyed without a checklist. BG3 Overlay is unavailable."
        case .balanced: "Standard rules with route, build, and encounter planning."
        case .tactician: "Harder fights where preparation and stronger builds matter."
        case .honour: "Single save, Legendary Actions, and no room for careless mistakes."
        case .custom: "Custom combinations vary, so warnings cannot match every rule mix."
        }
    }

    var showsHonourMechanics: Bool { self == .honour }
}

enum RouteRevealPolicy: String, Codable, CaseIterable, Identifiable {
    case everything
    case nextThree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Show everything"
        case .nextThree: "Only 3 tasks ahead"
        }
    }

    var detail: String {
        switch self {
        case .everything: "See the complete act route, decisions, and equipment challenges."
        case .nextThree: "Keep story details hidden beyond the next three route tasks; build gear stays visible."
        }
    }
}

struct ManualBuildLevel: Codable, Hashable, Identifiable {
    var id: Int { characterLevel }
    let characterLevel: Int
    var className: String
    var selections: [String: [String]] = [:]
}

struct ManualBuildPlan: Codable, Hashable {
    var name: String
    var abilityScores: AbilityScores
    var levels: [ManualBuildLevel]

    static func empty(name: String, scores: AbilityScores) -> ManualBuildPlan {
        ManualBuildPlan(
            name: name,
            abilityScores: scores,
            levels: (1...12).map { ManualBuildLevel(characterLevel: $0, className: "") }
        )
    }

    func classLevel(at characterLevel: Int) -> Int {
        guard let selectedClass = levels.first(where: { $0.characterLevel == characterLevel })?.className,
              !selectedClass.isEmpty else { return 0 }
        return levels.filter { $0.characterLevel <= characterLevel && $0.className == selectedClass }.count
    }

    mutating func setClass(_ className: String, at characterLevel: Int) {
        guard let index = levels.firstIndex(where: { $0.characterLevel == characterLevel }) else { return }
        let replacedClass = levels[index].className
        guard replacedClass != className else { return }
        levels[index].className = className
        levels[index].selections = [:]
        guard !className.isEmpty, index < levels.index(before: levels.endIndex) else { return }
        for futureIndex in levels.index(after: index)..<levels.endIndex {
            let futureClass = levels[futureIndex].className
            guard futureClass.isEmpty || futureClass == replacedClass else { break }
            if futureClass != className {
                levels[futureIndex].className = className
                levels[futureIndex].selections = [:]
            }
        }
    }

    var classSummary: String {
        let counts = Dictionary(grouping: levels.filter { !$0.className.isEmpty }, by: \.className)
            .mapValues(\.count)
        return counts.keys.sorted().map { "\($0) \(counts[$0] ?? 0)" }.joined(separator: " / ")
    }
}

struct BG3BuildOption: Identifiable, Hashable {
    let name: String
    let detail: String
    let systemImage: String
    var id: String { name }
    var artworkFilename: String { "\(BG3BuildArtwork.slug(for: name)).webp" }
}

@MainActor
enum BG3BuildArtwork {
    private static let cache = NSCache<NSString, NSImage>()

    nonisolated static func slug(for name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    static func image(for option: BG3BuildOption) -> NSImage? {
        let filename = option.artworkFilename
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/BuildOptionIcons", directoryHint: .isDirectory)
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "BuildOptionIcons/\(filename)"),
            sourceDirectory.appending(path: filename),
        ].compactMap { $0 }
        guard let image = candidates.lazy
            .filter({ FileManager.default.fileExists(atPath: $0.path) })
            .compactMap(NSImage.init(contentsOf:))
            .first else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }
}

struct BG3BuildChoiceGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let maximumSelections: Int
    let options: [BG3BuildOption]
    let requiredSelection: String?
    let requiresSelectionAtSameLevel: Bool
}

struct BG3ClassLevelDefinition {
    let features: [BG3BuildOption]
    let choices: [BG3BuildChoiceGroup]
}

struct BG3ClassDefinition: Identifiable {
    let name: String
    let systemImage: String
    var levels: [Int: BG3ClassLevelDefinition]
    var id: String { name }
}

enum BG3ClassCatalog {
    static let classNames = definitions.map(\.name)

    static func definition(named name: String) -> BG3ClassDefinition? {
        definitions.first { $0.name == name }
    }

    static let definitions: [BG3ClassDefinition] = [
        barbarian,
        bard,
        cleric,
        druid,
        fighter,
        monk,
        paladin,
        ranger,
        rogue,
        sorcerer,
        warlock,
        wizard,
    ]

    private enum Spellcasting {
        case none
        case full
        case prepared
        case half
    }

    private static let skills = options(
        [
            "Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception", "History",
            "Insight", "Intimidation", "Investigation", "Medicine", "Nature", "Perception",
            "Performance", "Persuasion", "Religion", "Sleight of Hand", "Stealth", "Survival",
        ],
        detail: "Skill proficiency",
        icon: "checkmark.seal.fill"
    )

    private static let magicalSecrets = options(
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
        ],
        detail: "Magical Secrets spell",
        icon: "sparkles"
    )

    private static let feats = options(
        [
            "Ability Improvement", "Actor", "Alert", "Athlete", "Charger", "Crossbow Expert",
            "Defensive Duellist", "Dual Wielder", "Dungeon Delver", "Durable", "Elemental Adept",
            "Great Weapon Master", "Heavily Armoured", "Heavy Armour Master", "Lightly Armoured",
            "Lucky", "Mage Slayer", "Magic Initiate: Bard", "Magic Initiate: Cleric",
            "Magic Initiate: Druid", "Magic Initiate: Sorcerer", "Magic Initiate: Warlock",
            "Magic Initiate: Wizard", "Martial Adept", "Medium Armour Master", "Mobile",
            "Moderately Armoured", "Performer", "Polearm Master", "Resilient", "Ritual Caster",
            "Savage Attacker", "Sentinel", "Sharpshooter", "Shield Master", "Skilled",
            "Spell Sniper", "Tavern Brawler", "Tough", "War Caster", "Weapon Master",
        ],
        detail: "BG3 feat",
        icon: "seal.fill"
    )

    private static let abilityImprovementOptions: [BG3BuildOption] = {
        var names = Ability.allCases.map { "+2 \($0.displayName)" }
        for first in Ability.allCases.indices {
            for second in Ability.allCases.indices where second > first {
                names.append("+1 \(Ability.allCases[first].displayName) / +1 \(Ability.allCases[second].displayName)")
            }
        }
        return options(names, detail: "Ability Improvement allocation", icon: "arrow.up.circle.fill")
    }()

    private static let abilityChoices = options(
        Ability.allCases.map(\.displayName),
        detail: "Ability choice",
        icon: "arrow.up.circle.fill"
    )

    private static let combatManoeuvres = options(
        [
            "Commander's Strike", "Disarming Attack", "Distracting Strike", "Evasive Footwork",
            "Feinting Attack", "Goading Attack", "Manoeuvring Attack", "Menacing Attack",
            "Precision Attack", "Pushing Attack", "Rally", "Riposte", "Sweeping Attack", "Trip Attack",
        ],
        detail: "Battle Master manoeuvre",
        icon: "burst.fill"
    )

    private static let fightingStyles = options(
        ["Archery", "Defence", "Duelling", "Great Weapon Fighting", "Protection", "Two-Weapon Fighting"],
        detail: "Fighting style",
        icon: "shield.fill"
    )

    private static var barbarian: BG3ClassDefinition {
        var result = classDefinition(
            "Barbarian", icon: "flame.fill",
            subclassLevel: 3,
            subclasses: ["Berserker", "Wildheart", "Wild Magic", "Path of Giants"],
            features: [
                1: ["Rage", "Unarmoured Defence"],
                2: ["Danger Sense", "Reckless Attack"],
                3: ["Additional Rage Charge"],
                5: ["Extra Attack", "Fast Movement"],
                6: ["Additional Rage Charge"],
                7: ["Feral Instinct"],
                8: ["Lands Stride: Difficult Terrain"],
                9: ["Brutal Critical"],
                10: ["Additional Rage Charge"],
                11: ["Relentless Rage"],
            ]
        )
        let hearts = options(
            ["Bear Heart", "Eagle Heart", "Elk Heart", "Tiger Heart", "Wolf Heart"],
            detail: "Wildheart Bestial Heart",
            icon: "pawprint.fill"
        )
        let aspects = options(
            ["Bear", "Chimpanzee", "Crocodile", "Eagle", "Elk", "Honey Badger", "Stallion", "Tiger", "Wolf", "Wolverine"],
            detail: "Wildheart Animal Aspect",
            icon: "hare.fill"
        )
        result.levels[3] = addingChoice(result.levels[3], group(
            "bestial-heart", "Bestial Heart", 1, hearts, requiredSelection: "Wildheart"
        ))
        result.levels[6] = addingChoice(result.levels[6], group(
            "animal-aspect-6", "Animal Aspect", 1, aspects, requiredSelection: "Wildheart"
        ))
        result.levels[10] = addingChoice(result.levels[10], group(
            "animal-aspect-10", "Additional Animal Aspect", 1, aspects, requiredSelection: "Wildheart"
        ))
        result.levels[6] = addingChoice(result.levels[6], group(
            "elemental-cleaver", "Elemental Cleaver", 1,
            options(["Acid", "Cold", "Fire", "Lightning", "Thunder"], detail: "Path of Giants element", icon: "bolt.fill"),
            requiredSelection: "Path of Giants"
        ))
        return result
    }

    private static var bard: BG3ClassDefinition {
        var result = classDefinition(
            "Bard", icon: "music.note",
            subclassLevel: 3,
            subclasses: ["College of Lore", "College of Valour", "College of Swords", "College of Glamour"],
            features: [
                1: ["Bardic Inspiration"],
                2: ["Jack of All Trades", "Song of Rest"],
                3: ["Expertise"],
                5: ["Font of Inspiration", "Improved Bardic Inspiration"],
                6: ["Countercharm"],
                10: ["Expertise", "Magical Secrets"],
            ],
            spellcaster: .full
        )
        result.levels[3] = addingChoice(result.levels[3], group("expertise-3", "Expertise", 2, skills))
        result.levels[10] = addingChoice(result.levels[10], group("expertise-10", "Expertise", 2, skills))
        result.levels[3] = addingChoice(result.levels[3], group(
            "lore-skills", "College of Lore Skills", 3, skills, requiredSelection: "College of Lore"
        ))
        result.levels[3] = addingChoice(result.levels[3], group(
            "swords-style", "College of Swords Fighting Style", 1,
            options(["Duelling", "Two-Weapon Fighting"], detail: "College of Swords style", icon: "shield.fill"),
            requiredSelection: "College of Swords"
        ))
        result.levels[6] = addingChoice(result.levels[6], group(
            "lore-magical-secrets", "Magical Secrets", 2, magicalSecrets,
            requiredSelection: "College of Lore"
        ))
        result.levels[10] = addingChoice(result.levels[10], group(
            "magical-secrets", "Magical Secrets", 2, magicalSecrets
        ))
        return result
    }

    private static var druid: BG3ClassDefinition {
        var result = classDefinition(
            "Druid", icon: "leaf.fill",
            subclassLevel: 2,
            subclasses: ["Circle of the Land", "Circle of the Moon", "Circle of Spores", "Circle of the Stars"],
            features: [
                1: ["Druidic"],
                2: ["Wild Shape"],
                4: ["Wild Shape: Deep Rothé"],
                5: ["Wild Strike"],
                8: ["Wild Shape: Sabre-Toothed Tiger"],
                10: ["Improved Wild Strike"],
            ],
            spellcaster: .prepared
        )
        let lands = options(
            ["Arctic", "Coast", "Desert", "Forest", "Grassland", "Mountain", "Swamp", "Underdark"],
            detail: "Circle of the Land terrain",
            icon: "map.fill"
        )
        for level in [3, 5, 7, 9] {
            result.levels[level] = addingChoice(result.levels[level], group(
                "land-\(level)", "Circle Spells Land", 1, lands,
                requiredSelection: "Circle of the Land"
            ))
        }
        return result
    }

    private static var cleric: BG3ClassDefinition {
        var result = classDefinition(
            "Cleric", icon: "sun.max.fill",
            subclassLevel: 1,
            subclasses: ["Life Domain", "Light Domain", "Trickery Domain", "Knowledge Domain", "Nature Domain", "Tempest Domain", "War Domain", "Death Domain"],
            features: [
                1: ["Channel Divinity"],
                2: ["Turn Undead"],
                5: ["Destroy Undead"],
                10: ["Divine Intervention"],
            ],
            spellcaster: .prepared
        )
        result.levels[10] = addingChoice(result.levels[10], group(
            "divine-intervention", "Divine Intervention", 1,
            options(
                ["Arm Thy Servant", "Golden Generosity", "Opulent Revival", "Sunder the Heretical"],
                detail: "One-use Divine Intervention",
                icon: "sun.max.fill"
            )
        ))
        return result
    }

    private static var monk: BG3ClassDefinition {
        var result = classDefinition(
            "Monk", icon: "hand.raised.fill",
            subclassLevel: 3,
            subclasses: ["Way of the Open Hand", "Way of Shadow", "Way of the Four Elements", "Way of the Drunken Master"],
            features: [
                1: ["Martial Arts", "Unarmoured Defence", "Flurry of Blows"],
                2: ["Patient Defence", "Step of the Wind", "Unarmoured Movement"],
                3: ["Deflect Missiles"],
                4: ["Slow Fall"],
                5: ["Extra Attack", "Stunning Strike"],
                6: ["Ki-Empowered Strikes"],
                7: ["Evasion", "Stillness of Mind"],
                9: ["Advanced Unarmoured Movement"],
                10: ["Purity of Body"],
            ]
        )
        let disciplines = options(
            [
                "Blade of Rime", "Chill of the Mountain", "Fangs of the Fire Snake",
                "Fist of Four Thunders", "Fist of Unbroken Air", "Rush of the Gale Spirits",
                "Shaping of the Ice", "Sphere of Elemental Balance", "Sweeping Cinder Strike",
                "Touch of the Storm", "Water Whip", "Clench of the North Wind",
                "Embrace of the Inferno", "Gong of the Summit", "Flames of the Phoenix",
                "Mist Stance", "Ride the Wind",
            ],
            detail: "Elemental Discipline",
            icon: "wind"
        )
        result.levels[3] = addingChoice(result.levels[3], group(
            "disciplines-3", "Elemental Disciplines", 3, disciplines,
            requiredSelection: "Way of the Four Elements"
        ))
        for level in [6, 9, 11] {
            result.levels[level] = addingChoice(result.levels[level], group(
                "disciplines-\(level)", "Additional Elemental Discipline", 1, disciplines,
                requiredSelection: "Way of the Four Elements"
            ))
        }
        return result
    }

    private static var fighter: BG3ClassDefinition {
        var result = classDefinition(
            "Fighter", icon: "shield.lefthalf.filled",
            subclassLevel: 3,
            subclasses: ["Battle Master", "Champion", "Eldritch Knight", "Arcane Archer"],
            features: [
                1: ["Second Wind"],
                2: ["Action Surge"],
                5: ["Extra Attack"],
                9: ["Indomitable"],
                11: ["Improved Extra Attack"],
            ]
        )
        result.levels[1] = addingChoice(result.levels[1], group("fighting-style", "Fighting Style", 1, fightingStyles))
        let arcaneShots = options(
            [
                "Banishing Arrow", "Beguiling Arrow", "Bursting Arrow", "Enfeebling Arrow",
                "Grasping Arrow", "Piercing Arrow", "Seeking Arrow", "Shadow Arrow",
            ],
            detail: "Arcane Shot",
            icon: "arrow.up.right.circle.fill"
        )
        result.levels[3] = addingChoice(result.levels[3], group(
            "manoeuvres-3", "Battle Manoeuvres", 3, combatManoeuvres,
            requiredSelection: "Battle Master"
        ))
        for level in [7, 10] {
            result.levels[level] = addingChoice(result.levels[level], group(
                "manoeuvres-\(level)", "Additional Battle Manoeuvres", 2, combatManoeuvres,
                requiredSelection: "Battle Master"
            ))
        }
        result.levels[3] = addingChoice(result.levels[3], group(
            "arcane-archer-cantrip", "Arcane Archer Cantrip", 1,
            options(["Guidance", "Light", "True Strike"], detail: "Arcane Archer cantrip", icon: "sparkle"),
            requiredSelection: "Arcane Archer"
        ))
        result.levels[3] = addingChoice(result.levels[3], group(
            "arcane-shots-3", "Arcane Shots", 3, arcaneShots,
            requiredSelection: "Arcane Archer"
        ))
        for level in [7, 10] {
            result.levels[level] = addingChoice(result.levels[level], group(
                "arcane-shots-\(level)", "Additional Arcane Shot", 1, arcaneShots,
                requiredSelection: "Arcane Archer"
            ))
        }
        result.levels[3] = addingChoice(result.levels[3], group(
            "eldritch-knight-cantrips", "Eldritch Knight Cantrips", 2,
            options(BG3SpellCatalog.byClassAndRank["Wizard"]?[0] ?? [], detail: "Eldritch Knight cantrip", icon: "sparkle"),
            requiredSelection: "Eldritch Knight"
        ))
        result.levels[3] = addingChoice(result.levels[3], group(
            "eldritch-knight-spells", "Eldritch Knight Spells", 3,
            options(BG3SpellCatalog.spells(for: "Wizard", from: 1, through: 1), detail: "Eldritch Knight spell", icon: "sparkles"),
            requiredSelection: "Eldritch Knight"
        ))
        for level in [4, 7, 8, 10, 11] {
            let rank = level >= 7 ? 2 : 1
            result.levels[level] = addingChoice(result.levels[level], group(
                "eldritch-knight-spell-\(level)", "Additional Eldritch Knight Spell", 1,
                options(
                    BG3SpellCatalog.spells(for: "Wizard", from: 1, through: rank),
                    detail: "Eldritch Knight spell · rank \(rank) or lower",
                    icon: "sparkles"
                ),
                requiredSelection: "Eldritch Knight"
            ))
        }
        result.levels[6] = addingFeat(to: result.levels[6], level: 6)
        return result
    }

    private static var paladin: BG3ClassDefinition {
        var result = classDefinition(
            "Paladin", icon: "shield.checkered",
            subclassLevel: 1,
            subclasses: ["Oath of the Ancients", "Oath of Devotion", "Oath of Vengeance", "Oathbreaker", "Oath of the Crown"],
            features: [
                1: ["Lay on Hands", "Channel Oath Charges"],
                2: ["Divine Smite"],
                3: ["Divine Health"],
                5: ["Extra Attack"],
                6: ["Aura of Protection"],
                9: ["Additional Channel Oath Charge"],
                10: ["Aura of Courage"],
                11: ["Improved Divine Smite"],
            ],
            spellcaster: .half
        )
        result.levels[2] = addingChoice(result.levels[2], group("fighting-style", "Fighting Style", 1, fightingStyles))
        return result
    }

    private static var ranger: BG3ClassDefinition {
        var result = classDefinition(
            "Ranger", icon: "scope",
            subclassLevel: 3,
            subclasses: ["Hunter", "Beast Master", "Gloom Stalker", "Swarmkeeper"],
            features: [
                1: ["Favoured Enemy", "Natural Explorer"],
                3: ["Primeval Awareness"],
                5: ["Extra Attack"],
                6: ["Favoured Enemy", "Natural Explorer"],
                8: ["Land's Stride: Difficult Terrain"],
                10: ["Hide in Plain Sight", "Favoured Enemy", "Natural Explorer"],
            ],
            spellcaster: .half
        )
        result.levels[2] = addingChoice(result.levels[2], group("fighting-style", "Fighting Style", 1, fightingStyles))
        result.levels[1] = addingChoice(result.levels[1], group(
            "favoured-enemy", "Favoured Enemy", 1,
            options(["Bounty Hunter", "Keeper of the Veil", "Mage Breaker", "Ranger Knight", "Sanctified Stalker"], detail: "Favoured enemy", icon: "scope")
        ))
        result.levels[1] = addingChoice(result.levels[1], group(
            "natural-explorer", "Natural Explorer", 1,
            options(["Beast Tamer", "Urban Tracker", "Wasteland Wanderer: Cold", "Wasteland Wanderer: Fire", "Wasteland Wanderer: Poison"], detail: "Natural explorer", icon: "map.fill")
        ))
        for level in [6, 10] {
            result.levels[level] = addingChoice(result.levels[level], group(
                "favoured-enemy-\(level)", "Favoured Enemy", 1,
                options(["Bounty Hunter", "Keeper of the Veil", "Mage Breaker", "Ranger Knight", "Sanctified Stalker"], detail: "Favoured enemy", icon: "scope")
            ))
            result.levels[level] = addingChoice(result.levels[level], group(
                "natural-explorer-\(level)", "Natural Explorer", 1,
                options(["Beast Tamer", "Urban Tracker", "Wasteland Wanderer: Cold", "Wasteland Wanderer: Fire", "Wasteland Wanderer: Poison"], detail: "Natural explorer", icon: "map.fill")
            ))
        }
        result.levels[3] = addingChoice(result.levels[3], group(
            "hunters-prey", "Hunter's Prey", 1,
            options(["Colossus Slayer", "Giant Killer", "Horde Breaker"], detail: "Hunter's Prey", icon: "scope"),
            requiredSelection: "Hunter"
        ))
        result.levels[7] = addingChoice(result.levels[7], group(
            "defensive-tactics", "Defensive Tactics", 1,
            options(["Escape the Horde", "Steel Will", "Multiattack Defence"], detail: "Hunter defensive tactic", icon: "shield.fill"),
            requiredSelection: "Hunter"
        ))
        result.levels[3] = addingChoice(result.levels[3], group(
            "beast-companion", "Primary Beast Companion", 1,
            options(["Bear", "Boar", "Dire Raven", "Wolf", "Wolf Spider"], detail: "Beast Master companion", icon: "pawprint.fill"),
            requiredSelection: "Beast Master"
        ))
        result.levels[3] = addingChoice(result.levels[3], group(
            "swarm", "Gathered Swarm", 1,
            options(["Cloud of Jellyfish", "Flurry of Moths", "Legion of Bees"], detail: "Swarmkeeper swarm", icon: "aqi.medium"),
            requiredSelection: "Swarmkeeper"
        ))
        return result
    }

    private static var rogue: BG3ClassDefinition {
        var result = classDefinition(
            "Rogue", icon: "eye.slash.fill",
            subclassLevel: 3,
            subclasses: ["Thief", "Arcane Trickster", "Assassin", "Swashbuckler"],
            features: [
                1: ["Sneak Attack", "Expertise"],
                2: ["Cunning Action"],
                5: ["Uncanny Dodge"],
                6: ["Expertise"],
                7: ["Evasion"],
                11: ["Reliable Talent"],
            ]
        )
        result.levels[1] = addingChoice(result.levels[1], group("expertise-1", "Expertise", 2, skills))
        result.levels[6] = addingChoice(result.levels[6], group("expertise-6", "Expertise", 2, skills))
        result.levels[3] = addingChoice(result.levels[3], group(
            "arcane-trickster-cantrips", "Arcane Trickster Cantrips", 2,
            options(BG3SpellCatalog.byClassAndRank["Wizard"]?[0] ?? [], detail: "Arcane Trickster cantrip", icon: "sparkle"),
            requiredSelection: "Arcane Trickster"
        ))
        result.levels[3] = addingChoice(result.levels[3], spellGroup(
            for: "Wizard", classLevel: 1, maximum: 3,
            id: "arcane-trickster-spells", title: "Arcane Trickster Spells",
            requiredSelection: "Arcane Trickster"
        ))
        for level in [4, 7, 8, 10, 11] {
            let rank = level >= 7 ? 2 : 1
            result.levels[level] = addingChoice(result.levels[level], group(
                "arcane-trickster-spell-\(level)", "Additional Arcane Trickster Spell", 1,
                options(
                    BG3SpellCatalog.spells(for: "Wizard", from: 1, through: rank),
                    detail: "Arcane Trickster spell · rank \(rank) or lower",
                    icon: "sparkles"
                ),
                requiredSelection: "Arcane Trickster"
            ))
        }
        result.levels[10] = addingFeat(to: result.levels[10], level: 10)
        return result
    }

    private static var sorcerer: BG3ClassDefinition {
        var result = classDefinition(
            "Sorcerer", icon: "sparkles",
            subclassLevel: 1,
            subclasses: ["Draconic Bloodline", "Wild Magic", "Storm Sorcery", "Shadow Magic"],
            features: [
                1: ["Sorcery Points"],
                2: ["Create Spell Slot", "Create Sorcery Points"],
                3: ["Metamagic"],
                10: ["Metamagic"],
            ],
            spellcaster: .full
        )
        let metamagic = options(
            ["Careful Spell", "Distant Spell", "Extended Spell", "Twinned Spell", "Heightened Spell", "Quickened Spell", "Subtle Spell"],
            detail: "Metamagic",
            icon: "wand.and.stars"
        )
        result.levels[2] = addingChoice(result.levels[2], group("metamagic-2", "Metamagic", 2, metamagic))
        result.levels[3] = addingChoice(result.levels[3], group("metamagic-3", "Additional Metamagic", 1, metamagic))
        result.levels[10] = addingChoice(result.levels[10], group("metamagic-10", "Additional Metamagic", 1, metamagic))
        result.levels[1] = addingChoice(result.levels[1], group(
            "draconic-ancestry", "Draconic Ancestry", 1,
            options(
                [
                    "Red (Fire)", "Black (Acid)", "Blue (Lightning)", "White (Cold)", "Green (Poison)",
                    "Gold (Fire)", "Silver (Cold)", "Bronze (Lightning)", "Copper (Acid)", "Brass (Fire)",
                ],
                detail: "Draconic ancestry",
                icon: "flame.fill"
            ),
            requiredSelection: "Draconic Bloodline"
        ))
        return result
    }

    private static var warlock: BG3ClassDefinition {
        var result = classDefinition(
            "Warlock", icon: "moon.stars.fill",
            subclassLevel: 1,
            subclasses: ["The Fiend", "The Great Old One", "The Archfey", "The Hexblade"],
            features: [
                1: ["Pact Magic"],
                2: ["Eldritch Invocations"],
                3: ["Pact Boon"],
                5: ["Deepened Pact"],
                11: ["Mystic Arcanum"],
            ],
            spellcaster: .full
        )
        let invocations = options(
            [
                "Agonising Blast", "Armour of Shadows", "Beast Speech", "Beguiling Influence",
                "Devil's Sight", "Fiendish Vigour", "Mask of Many Faces", "One with Shadows",
                "Repelling Blast", "Thief of Five Fates", "Book of Ancient Secrets", "Dreadful Word",
                "Minions of Chaos", "Mire the Mind", "Otherworldly Leap", "Sculptor of Flesh",
                "Sign of Ill Omen", "Whispers of the Grave", "Lifedrinker",
            ],
            detail: "Eldritch invocation",
            icon: "eye.fill"
        )
        result.levels[2] = addingChoice(result.levels[2], group("invocations-2", "Eldritch Invocations", 2, invocations))
        result.levels[5] = addingChoice(result.levels[5], group("invocations-5", "Additional Invocation", 1, invocations))
        result.levels[7] = addingChoice(result.levels[7], group("invocations-7", "Additional Invocation", 1, invocations))
        result.levels[9] = addingChoice(result.levels[9], group("invocations-9", "Additional Invocation", 1, invocations))
        result.levels[12] = addingChoice(result.levels[12], group("invocations-12", "Additional Invocation", 1, invocations))
        result.levels[3] = addingChoice(result.levels[3], group(
            "pact-boon", "Pact Boon", 1,
            options(["Pact of the Blade", "Pact of the Chain", "Pact of the Tome"], detail: "Pact boon", icon: "book.closed.fill")
        ))
        result.levels[11] = addingChoice(result.levels[11], group(
            "mystic-arcanum", "Mystic Arcanum", 1,
            options(BG3SpellCatalog.byClassAndRank["Warlock"]?[6] ?? [], detail: "6th-level Mystic Arcanum", icon: "moon.stars.fill")
        ))
        return result
    }

    private static var wizard: BG3ClassDefinition {
        classDefinition(
            "Wizard", icon: "wand.and.stars",
            subclassLevel: 2,
            subclasses: [
                "Abjuration School", "Bladesinging", "Conjuration School", "Divination School",
                "Enchantment School", "Evocation School", "Illusion School", "Necromancy School",
                "Transmutation School",
            ],
            features: [
                1: ["Arcane Recovery", "Spellbook", "Scroll Transcription"],
            ],
            spellcaster: .full
        )
    }

    private static func classDefinition(
        _ name: String,
        icon: String,
        subclassLevel: Int,
        subclasses: [String],
        features: [Int: [String]],
        spellcaster: Spellcasting = .none
    ) -> BG3ClassDefinition {
        var levels: [Int: BG3ClassLevelDefinition] = [:]
        for level in 1...12 {
            var groups: [BG3BuildChoiceGroup] = []
            if level == subclassLevel {
                groups.append(group(
                    "subclass", "Subclass", 1,
                    options(subclasses, detail: "\(name) subclass", icon: "shield.lefthalf.filled")
                ))
            }
            if [4, 8, 12].contains(level) {
                groups += featChoiceGroups(level: level)
            }
            if spellcaster != .none {
                let rank = maximumSpellRank(classLevel: level, spellcasting: spellcaster)
                let count = spellSelectionCount(className: name, classLevel: level, casting: spellcaster)
                if count > 0 {
                    groups.append(spellGroup(
                        for: name, classLevel: level, maximum: count,
                        id: "spells-\(level)", title: spellcaster == .prepared ? "Prepared Spells" : "Learn Spells"
                    ))
                }
                if rank > 0, level == 1 {
                    groups.append(group(
                        "cantrips", "Cantrips", cantripCount(className: name),
                        options(BG3SpellCatalog.byClassAndRank[name]?[0] ?? [], detail: "\(name) cantrip", icon: "sparkle")
                    ))
                }
            }
            levels[level] = BG3ClassLevelDefinition(
                features: options(features[level] ?? [], detail: "\(name) class feature", icon: icon),
                choices: groups
            )
        }
        return BG3ClassDefinition(name: name, systemImage: icon, levels: levels)
    }

    private static func spellGroup(
        for className: String,
        classLevel: Int,
        maximum: Int,
        id: String,
        title: String,
        requiredSelection: String? = nil
    ) -> BG3BuildChoiceGroup {
        let casting: Spellcasting = ["Paladin", "Ranger"].contains(className) ? .half : .full
        let rank = maximumSpellRank(classLevel: classLevel, spellcasting: casting)
        return group(
            id, title, maximum,
            options(BG3SpellCatalog.spells(for: className, from: 1, through: rank), detail: "\(className) spell · rank \(rank) or lower", icon: "sparkles"),
            requiredSelection: requiredSelection
        )
    }

    private static func maximumSpellRank(classLevel: Int, spellcasting: Spellcasting) -> Int {
        switch spellcasting {
        case .none: 0
        case .full, .prepared: min(6, (classLevel + 1) / 2)
        case .half: classLevel < 2 ? 0 : min(3, (classLevel + 3) / 4)
        }
    }

    private static func spellSelectionCount(className: String, classLevel: Int, casting: Spellcasting) -> Int {
        if casting == .prepared { return classLevel == 1 ? 4 : 2 }
        if className == "Warlock" { return classLevel == 1 ? 2 : ([2, 3, 4, 5, 7, 9].contains(classLevel) ? 1 : 0) }
        if className == "Bard" { return classLevel == 1 ? 4 : 1 }
        if className == "Sorcerer" { return classLevel == 1 ? 2 : 1 }
        if casting == .half { return classLevel >= 2 ? 1 : 0 }
        if className == "Wizard" { return classLevel == 1 ? 6 : 2 }
        return 0
    }

    private static func cantripCount(className: String) -> Int {
        switch className {
        case "Bard", "Cleric", "Druid", "Warlock": 2
        case "Sorcerer": 4
        case "Wizard": 3
        default: 0
        }
    }

    private static func addingFeat(to level: BG3ClassLevelDefinition?, level number: Int) -> BG3ClassLevelDefinition {
        let choices = (level?.choices ?? []) + featChoiceGroups(level: number)
        return BG3ClassLevelDefinition(features: level?.features ?? [], choices: choices)
    }

    private static func featChoiceGroups(level: Int) -> [BG3BuildChoiceGroup] {
        let local = true
        var groups = [
            group("feat-\(level)", "Feat or Ability Improvement", 1, feats),
            group(
                "ability-improvement-\(level)", "Ability Improvement Allocation", 1,
                abilityImprovementOptions,
                requiredSelection: "Ability Improvement",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "athlete-ability-\(level)", "Athlete Ability", 1,
                options(["Strength", "Dexterity"], detail: "Athlete +1 ability", icon: "figure.run"),
                requiredSelection: "Athlete",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "elemental-adept-\(level)", "Elemental Adept Damage", 1,
                options(["Acid", "Cold", "Fire", "Lightning", "Thunder"], detail: "Elemental Adept type", icon: "flame.fill"),
                requiredSelection: "Elemental Adept",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "moderately-armoured-\(level)", "Moderately Armoured Ability", 1,
                options(["Strength", "Dexterity"], detail: "Moderately Armoured +1 ability", icon: "shield.fill"),
                requiredSelection: "Moderately Armoured",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "resilient-\(level)", "Resilient Ability", 1, abilityChoices,
                requiredSelection: "Resilient",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "skilled-\(level)", "Skilled Proficiencies", 3, skills,
                requiredSelection: "Skilled",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "tavern-brawler-\(level)", "Tavern Brawler Ability", 1,
                options(["Strength", "Constitution"], detail: "Tavern Brawler +1 ability", icon: "hand.raised.fill"),
                requiredSelection: "Tavern Brawler",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "martial-adept-\(level)", "Martial Adept Manoeuvres", 2, combatManoeuvres,
                requiredSelection: "Martial Adept",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "ritual-caster-\(level)", "Ritual Caster Spells", 2,
                options(
                    ["Disguise Self", "Enhance Leap", "Find Familiar", "Longstrider", "Speak with Animals", "Speak with Dead"],
                    detail: "Ritual Caster spell",
                    icon: "book.closed.fill"
                ),
                requiredSelection: "Ritual Caster",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "spell-sniper-\(level)", "Spell Sniper Cantrip", 1,
                options(
                    ["Bone Chill", "Eldritch Blast", "Fire Bolt", "Ray of Frost", "Shocking Grasp", "Thorn Whip"],
                    detail: "Spell Sniper cantrip",
                    icon: "scope"
                ),
                requiredSelection: "Spell Sniper",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "weapon-master-ability-\(level)", "Weapon Master Ability", 1,
                options(["Strength", "Dexterity"], detail: "Weapon Master +1 ability", icon: "arrow.up.circle.fill"),
                requiredSelection: "Weapon Master",
                requiresSelectionAtSameLevel: local
            ),
            group(
                "weapon-master-proficiencies-\(level)", "Weapon Master Proficiencies", 4,
                options(
                    [
                        "Battleaxes", "Clubs", "Daggers", "Darts", "Flails", "Glaives", "Greataxes",
                        "Greatclubs", "Greatswords", "Halberds", "Hand Crossbows", "Handaxes",
                        "Heavy Crossbows", "Javelins", "Light Crossbows", "Light Hammers",
                        "Longbows", "Longswords", "Maces", "Mauls", "Morningstars", "Pikes",
                        "Quarterstaves", "Rapiers", "Scimitars", "Shortbows", "Shortswords",
                        "Sickles", "Slings", "Spears", "Tridents", "War Picks", "Warhammers",
                    ],
                    detail: "Weapon proficiency",
                    icon: "shield.lefthalf.filled"
                ),
                requiredSelection: "Weapon Master",
                requiresSelectionAtSameLevel: local
            ),
        ]

        for className in ["Bard", "Cleric", "Druid", "Sorcerer", "Warlock", "Wizard"] {
            let requirement = "Magic Initiate: \(className)"
            groups.append(group(
                "magic-initiate-\(className.lowercased())-cantrips-\(level)",
                "\(requirement) Cantrips",
                2,
                options(BG3SpellCatalog.byClassAndRank[className]?[0] ?? [], detail: "\(className) cantrip", icon: "sparkle"),
                requiredSelection: requirement,
                requiresSelectionAtSameLevel: local
            ))
            groups.append(group(
                "magic-initiate-\(className.lowercased())-spell-\(level)",
                "\(requirement) Spell",
                1,
                options(BG3SpellCatalog.byClassAndRank[className]?[1] ?? [], detail: "\(className) level 1 spell", icon: "sparkles"),
                requiredSelection: requirement,
                requiresSelectionAtSameLevel: local
            ))
        }
        return groups
    }

    private static func addingChoice(
        _ level: BG3ClassLevelDefinition?,
        _ choice: BG3BuildChoiceGroup
    ) -> BG3ClassLevelDefinition {
        BG3ClassLevelDefinition(features: level?.features ?? [], choices: (level?.choices ?? []) + [choice])
    }

    private static func group(
        _ id: String,
        _ title: String,
        _ maximum: Int,
        _ options: [BG3BuildOption],
        requiredSelection: String? = nil,
        requiresSelectionAtSameLevel: Bool = false
    ) -> BG3BuildChoiceGroup {
        BG3BuildChoiceGroup(
            id: id,
            title: title,
            maximumSelections: maximum,
            options: options,
            requiredSelection: requiredSelection,
            requiresSelectionAtSameLevel: requiresSelectionAtSameLevel
        )
    }

    private static func options(_ names: [String], detail: String, icon: String) -> [BG3BuildOption] {
        names.map { BG3BuildOption(name: $0, detail: detail, systemImage: icon) }
    }
}

struct BG3ChoiceIcon: View {
    let option: BG3BuildOption
    let selected: Bool

    private var hue: Double {
        Double(abs(option.name.hashValue % 360)) / 360
    }

    var body: some View {
        Group {
            if let artwork = BG3BuildArtwork.image(for: option) {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : BG3Theme.parchment)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 0.65, brightness: selected ? 0.78 : 0.46),
                                BG3Theme.ink,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
            .frame(width: 40, height: 40)
            .background(BG3Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? BG3Theme.gold : BG3Theme.bronze, lineWidth: selected ? 2 : 0.8)
            )
            .shadow(color: selected ? BG3Theme.gold.opacity(0.35) : .clear, radius: 4)
            .accessibilityHidden(true)
    }
}
