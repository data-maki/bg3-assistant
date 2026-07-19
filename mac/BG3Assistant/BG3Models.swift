import Foundation

enum CheckpointDisposition: String, Codable, CaseIterable {
    case pending
    case completed
    case skipped
    /// Bulk-marked by mid-run catch-up: resolved before the assistant was
    /// installed, assumed to have followed the guide's recommended path.
    /// Satisfies dependencies (including outcome requirements) but renders
    /// distinctly so the player can revisit and record what really happened.
    case caughtUp

    var countsAsCompleted: Bool { self == .completed || self == .caughtUp }
}

struct GuideSource: Codable, Hashable {
    let sheet: String
    let row: Int?
    let url: String
}

struct HonorDecision: Codable, Hashable {
    let text: String
    let kind: String
}

struct DecisionOption: Codable, Hashable {
    let label: String
    let benefits: [String]
    let costs: [String]
}

struct WalkthroughDecision: Codable, Hashable {
    let prompt: String
    let recommended: DecisionOption
    let alternatives: [DecisionOption]
    let reversible: Bool
    let authority: String
}

struct IncidentProtocol: Codable, Hashable {
    let trigger: String
    let safeActions: [String]
    let never: String
    let escape: String
    let honorDelta: String
    let postFight: [String]
    let authority: String
    let sourceUrl: String
}

struct RiskReward: Codable, Hashable {
    let reward: String
    let risk: String
    let skipCost: String
    let returnBy: String
}

struct WalkthroughDependency: Codable, Hashable {
    let stepId: String
    let kind: String
    let reason: String
    let requiredOutcome: String?
}

struct WalkthroughStep: Codable, Identifiable, Hashable {
    let id: String
    let order: Int
    let phase: String
    let phaseOrder: Int
    let title: String
    let kind: String
    let importance: String
    let region: String
    let area: String
    let minimumLevel: Int
    let summary: String
    let avoid: String
    let why: String
    let rewards: [String]
    let completionChecks: [String]
    let prerequisites: [String]
    let dependencies: [WalkthroughDependency]
    let checkpointId: String?
    let markerId: String?
    let decision: WalkthroughDecision?
    let incident: IncidentProtocol?
    let riskReward: RiskReward?
    let authority: String
    let sourceLabel: String
    let sourceUrl: String
}

/// What the player actually does at a route step: swing swords, talk, or be
/// ready for either. Derived from reviewed data, not guessed — a conversation
/// with a run-ender protocol can turn hostile, and a fight with a reviewed
/// decision starts as a conversation.
enum StepEncounter {
    case fight
    case talk
    case fightAndTalk
    case explore
    case pickup
    case gate

    static func classify(_ step: WalkthroughStep) -> StepEncounter {
        let isFight = step.kind == "major_fight" || step.kind == "mini_fight"
        let hasTalk = step.kind == "dialogue" || step.kind == "decision" || (isFight && step.decision != nil)
        let canTurnHostile = step.incident != nil
        if isFight { return hasTalk ? .fightAndTalk : .fight }
        if hasTalk { return canTurnHostile ? .fightAndTalk : .talk }
        switch step.kind {
        case "pickup": return .pickup
        case "gate": return .gate
        default: return .explore
        }
    }

    var label: String {
        switch self {
        case .fight: "FIGHT"
        case .talk: "TALK"
        case .fightAndTalk: "TALK · FIGHT"
        case .explore: "EXPLORE"
        case .pickup: "PICKUP"
        case .gate: "GATE"
        }
    }

    var icon: String {
        switch self {
        case .fight: "burst.fill"
        case .talk: "bubble.left.and.bubble.right.fill"
        case .fightAndTalk: "exclamationmark.bubble.fill"
        case .explore: "figure.walk"
        case .pickup: "bag.fill"
        case .gate: "checkmark.shield.fill"
        }
    }

    /// One-line hint for the mixed case, shown under the title.
    var hint: String? {
        self == .fightAndTalk ? "Starts as a conversation — can turn into a fight" : nil
    }
}

struct RouteCheckpoint: Codable, Identifiable, Hashable {
    let id: String
    let routeOrder: Int
    let name: String
    let area: String
    let region: String
    let x: Int?
    let y: Int?
    let minimumLevel: Int
    let importance: String
    let danger: String
    let enemies: String
    let advice: String
    let legendaryAction: String?
    let failureConditions: [String]
    let preparation: [String]
    let completionChecks: [String]
    let irreversibleWarnings: [String]
    let prerequisites: [String]
    let notes: [String]
    let honorDecisions: [HonorDecision]
    let source: GuideSource
}

struct LevelActivityPlan {
    let activityLabel: String
    let phaseName: String
    let recommendation: RouteCheckpoint
    let safeXP: [RouteCheckpoint]
    let coreChallenge: RouteCheckpoint?
    let gateAdvice: String
}

struct BuildLevel: Codable, Hashable {
    let level: Int
    let take: String
    let subclassChoice: String
    let choices: String
    let tactics: String
    let confidence: String
    var abilityScoreReset: AbilityScores? = nil
}

struct AbilitySetupPlan: Codable, Hashable, Identifiable {
    let id: String
    let level: Int
    let label: String
    let reason: String
    let pointBuyScores: AbilityScores
    let bonusTwo: Ability
    let bonusOne: Ability
    let finalScores: AbilityScores
    let firstClass: String
    let classOrder: String
}

enum AbilityPlanSourceKind: String, Codable, Hashable {
    case asi
    case feat
    case permanent
    case equipment
    case consumable

    var label: String {
        switch self {
        case .asi: "Ability improvement"
        case .feat: "Feat"
        case .permanent: "Permanent"
        case .equipment: "Equipment"
        case .consumable: "Consumable"
        }
    }
}

struct AbilityPlanSource: Codable, Hashable, Identifiable {
    let id: String
    let ability: Ability
    let kind: AbilityPlanSourceKind
    let mode: AbilityModifierMode
    let value: Int
    let label: String
    var minimumAct: Int = 1
    var minimumLevel: Int = 1
    var maximumLevel: Int? = nil
    var itemKey: String? = nil
    var uniqueAcrossParty: Bool = false
    var note: String = ""

    func applies(at level: Int) -> Bool {
        level >= minimumLevel && (maximumLevel == nil || level <= maximumLevel!)
    }
}

struct BuildGear: Codable, Hashable, Identifiable {
    var id: String { "\(item)|\(region)" }
    let item: String
    let slot: String
    let priority: String
    let act: Int
    let region: String
    let acquisition: String
    let why: String
    let source: String
    var minimumLevel: Int? = nil
    var maximumLevel: Int? = nil
    var requirement: String? = nil
    var mapObjective: Bool? = nil
    var alternative: String? = nil
    // Wiki-sourced (data/item_effects.json): what the item does + where it is.
    var effect: String? = nil
    var acquire: String? = nil
    var wiki: String? = nil
    var icon: String? = nil  // path under the configured backend, e.g. /map-assets/icons/x.webp
    var gameX: Int? = nil
    var gameY: Int? = nil

    func isAvailable(at level: Int) -> Bool {
        level >= (minimumLevel ?? 1) && (maximumLevel == nil || level <= maximumLevel!)
    }

    var isMapObjective: Bool { mapObjective ?? true }
    var itemKey: String {
        item
            .replacingOccurrences(of: #"\s*x\d+$"#, with: "", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// One catalog item served by GET /api/items — item facts only (no
/// per-build opinions). Decoded with convertFromSnakeCase like RoutePayload.
struct ItemSummary: Codable, Hashable, Identifiable {
    var id: String { itemKey }
    let itemKey: String
    let name: String
    let slot: String
    let act: Int
    var region: String = ""
    var acquisition: String = ""
    var gameX: Int? = nil
    var gameY: Int? = nil
    var mapObjective: Bool = true
    var effect: String = ""
    var acquire: String = ""
    var wiki: String = ""
    var icon: String = ""
    var source: String = ""
}

/// A player-chosen equipment goal. Mirrors `focusedWalkthroughStepId`:
/// player-owned intent, separate from the route recommendation. One at a
/// time; setting a new target replaces the old one.
struct GearTarget: Codable, Hashable {
    let memberId: String
    let buildId: String
    let gearId: String
}

struct BuildSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let honorStatus: String
    let role: String
    let finalSplit: String
    let classProgression: String
    let startingAbilities: String
    var startingAbilityScores: AbilityScores? = nil
    var targetAbilityScores: AbilityScores? = nil
    var targetAbilityNote: String? = nil
    var abilitySetups: [AbilitySetupPlan]? = nil
    var abilitySources: [AbilityPlanSource]? = nil
    let playPattern: String
    let caveat: String
    let source: String
    let levels: [BuildLevel]
    let gear: [BuildGear]
}

struct AbilityScores: Codable, Hashable {
    var strength: Int
    var dexterity: Int
    var constitution: Int
    var intelligence: Int
    var wisdom: Int
    var charisma: Int

    static let customDefault = AbilityScores(
        strength: 17, dexterity: 15, constitution: 14,
        intelligence: 10, wisdom: 10, charisma: 8
    )

    static func forClass(_ className: String?) -> AbilityScores {
        switch className?.lowercased() {
        case "barbarian": .init(strength: 17, dexterity: 13, constitution: 15, intelligence: 8, wisdom: 12, charisma: 10)
        case "bard": .init(strength: 8, dexterity: 15, constitution: 13, intelligence: 12, wisdom: 10, charisma: 17)
        case "cleric": .init(strength: 10, dexterity: 14, constitution: 15, intelligence: 8, wisdom: 17, charisma: 10)
        case "druid": .init(strength: 10, dexterity: 14, constitution: 15, intelligence: 8, wisdom: 17, charisma: 10)
        case "fighter": .init(strength: 17, dexterity: 13, constitution: 15, intelligence: 10, wisdom: 12, charisma: 8)
        case "monk": .init(strength: 12, dexterity: 17, constitution: 14, intelligence: 8, wisdom: 14, charisma: 10)
        case "paladin": .init(strength: 17, dexterity: 10, constitution: 13, intelligence: 8, wisdom: 10, charisma: 16)
        case "ranger": .init(strength: 10, dexterity: 17, constitution: 14, intelligence: 8, wisdom: 16, charisma: 8)
        case "rogue": .init(strength: 8, dexterity: 17, constitution: 14, intelligence: 13, wisdom: 13, charisma: 10)
        case "sorcerer": .init(strength: 8, dexterity: 13, constitution: 15, intelligence: 12, wisdom: 10, charisma: 17)
        case "warlock": .init(strength: 8, dexterity: 14, constitution: 14, intelligence: 12, wisdom: 10, charisma: 17)
        case "wizard": .init(strength: 8, dexterity: 13, constitution: 15, intelligence: 17, wisdom: 10, charisma: 12)
        default: .customDefault
        }
    }
}

struct ImportedBuild: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sourceUrl: String
    let build: BuildSummary
}

struct LoadoutImportRequest: Encodable {
    let url: String
    let persist = true
}

struct AppTransactionAuthRequest: Encodable {
    let signedAppTransaction: String
}

struct BuildImportQuota: Codable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
}

struct CompanionAuthResponse: Decodable {
    let authenticated: Bool
    let expiresAt: Int
    let buildImports: BuildImportQuota
}

struct StoryCompanion: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let defaultClass: String

    static let origins = [
        StoryCompanion(name: "Shadowheart", defaultClass: "Cleric"),
        StoryCompanion(name: "Lae'zel", defaultClass: "Fighter"),
        StoryCompanion(name: "Astarion", defaultClass: "Rogue"),
        StoryCompanion(name: "Gale", defaultClass: "Wizard"),
        StoryCompanion(name: "Wyll", defaultClass: "Warlock"),
        StoryCompanion(name: "Karlach", defaultClass: "Barbarian"),
        StoryCompanion(name: "Dark Urge", defaultClass: "Sorcerer"),
    ]

    static let recruitable = [
        StoryCompanion(name: "Halsin", defaultClass: "Druid"),
        StoryCompanion(name: "Minthara", defaultClass: "Paladin"),
        StoryCompanion(name: "Jaheira", defaultClass: "Druid"),
        StoryCompanion(name: "Minsc", defaultClass: "Ranger"),
    ]

    static let all = origins + recruitable
}

struct WithersHireling: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let race: String
    let defaultClass: String

    var defaultAbilityScores: AbilityScores { .forClass(defaultClass) }

    static let all = [
        WithersHireling(name: "Eldra Luthrinn", race: "Gold Dwarf", defaultClass: "Barbarian"),
        WithersHireling(name: "Brinna Brightsong", race: "Lightfoot Halfling", defaultClass: "Bard"),
        WithersHireling(name: "Zenith Feur'sel", race: "High Elf", defaultClass: "Cleric"),
        WithersHireling(name: "Danton", race: "Mephistopheles Tiefling", defaultClass: "Druid"),
        WithersHireling(name: "Varanna Sunblossom", race: "Wood Half-Elf", defaultClass: "Fighter"),
        WithersHireling(name: "Sina'zith", race: "Githyanki", defaultClass: "Monk"),
        WithersHireling(name: "Kerz", race: "Half-Orc", defaultClass: "Paladin"),
        WithersHireling(name: "Ver'yll Wenkiir", race: "Seldarine Drow", defaultClass: "Ranger"),
        WithersHireling(name: "Maddala Deadeye", race: "Human", defaultClass: "Rogue"),
        WithersHireling(name: "Jacelyn", race: "High Half-Elf", defaultClass: "Sorcerer"),
        WithersHireling(name: "Kree Derryck", race: "Duergar", defaultClass: "Warlock"),
        WithersHireling(name: "Sir Fuzzalump", race: "Rock Gnome", defaultClass: "Wizard"),
    ]

    static func matching(_ name: String) -> WithersHireling? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

enum RosterStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case camp
    case unrecruited
    case unavailable
    case dead
    case departed

    var id: String { rawValue }
    var canBeActive: Bool { self == .active || self == .camp || self == .unrecruited }
}

struct PartyMember: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var level: Int
    var buildId: String?
    var preparedTags: [String]
    var className: String?
    var status: RosterStatus? = nil
    var roleOverride: String? = nil
    var isCustom: Bool? = nil
    var abilityScores: AbilityScores? = nil
    var isHireling: Bool? = nil
    var sourceLoadoutId: String? = nil
    var abilityModifiers: [AbilityModifier]? = nil
    var usesBuildAbilityScores: Bool? = nil
    var appliedAbilitySetupId: String? = nil

    var rosterStatus: RosterStatus { status ?? .active }

    var effectiveAbilityScores: AbilityScores {
        abilityScores ?? .forClass(className)
    }
}

/// Everything party planning owns, as one value: snapshot and restore go
/// through this single projection so undo can never miss a field.
struct PartyPlan {
    var roster: [PartyMember]
    var equippedByMember: [String: Set<String>]
    var gearAssignmentOverrides: [String: String]
    var plannedSlotOverrides: [String: [String: String]]
    var gearTarget: GearTarget?
}

/// Tolerant decoding: every field falls back to its default when absent, so
/// tightening a field to non-optional can never brick an existing run
/// snapshot. Lives in an extension so the synthesized memberwise/default
/// initializers and encoder survive.
extension HonorRun {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, guideVersion, party, roster, storyOutcomes,
             includeCampPlans, equippedByMember, equipmentOwnershipKnown,
             gearAssignmentOverrides, plannedSlotOverrides, progress,
             walkthroughProgress, walkthroughOutcomes, focusedWalkthroughStepId,
             gearTarget, selectedCheckpointId, selectedAct, actGearReview,
             actTransitions, finalActRecord, mapRegion, mutedCheckpointIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HonorRun()
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? defaults.id
        name = try container.decodeIfPresent(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        guideVersion = try container.decodeIfPresent(String.self, forKey: .guideVersion) ?? ""
        party = try container.decodeIfPresent([PartyMember].self, forKey: .party) ?? defaults.party
        roster = try container.decodeIfPresent([PartyMember].self, forKey: .roster)
        storyOutcomes = try container.decodeIfPresent(Set<String>.self, forKey: .storyOutcomes) ?? []
        includeCampPlans = try container.decodeIfPresent(Bool.self, forKey: .includeCampPlans) ?? false
        equippedByMember = try container.decodeIfPresent([String: Set<String>].self, forKey: .equippedByMember) ?? [:]
        equipmentOwnershipKnown = try container.decodeIfPresent(Bool.self, forKey: .equipmentOwnershipKnown) ?? false
        gearAssignmentOverrides = try container.decodeIfPresent([String: String].self, forKey: .gearAssignmentOverrides) ?? [:]
        plannedSlotOverrides = try container.decodeIfPresent([String: [String: String]].self, forKey: .plannedSlotOverrides) ?? [:]
        progress = try container.decodeIfPresent([String: CheckpointProgress].self, forKey: .progress) ?? [:]
        walkthroughProgress = try container.decodeIfPresent([String: CheckpointDisposition].self, forKey: .walkthroughProgress) ?? [:]
        walkthroughOutcomes = try container.decodeIfPresent([String: String].self, forKey: .walkthroughOutcomes) ?? [:]
        focusedWalkthroughStepId = try container.decodeIfPresent(String.self, forKey: .focusedWalkthroughStepId)
        gearTarget = try container.decodeIfPresent(GearTarget.self, forKey: .gearTarget)
        selectedCheckpointId = try container.decodeIfPresent(String.self, forKey: .selectedCheckpointId)
        selectedAct = try container.decodeIfPresent(Int.self, forKey: .selectedAct) ?? 1
        actGearReview = try container.decodeIfPresent([Int: [String: ActGearReviewStatus]].self, forKey: .actGearReview) ?? [:]
        actTransitions = try container.decodeIfPresent([ActTransitionRecord].self, forKey: .actTransitions) ?? []
        finalActRecord = try container.decodeIfPresent(ActTransitionRecord.self, forKey: .finalActRecord)
        mapRegion = try container.decodeIfPresent(String.self, forKey: .mapRegion) ?? "Wilderness"
        mutedCheckpointIds = try container.decodeIfPresent(Set<String>.self, forKey: .mutedCheckpointIds) ?? []
    }

    var partyPlan: PartyPlan {
        get {
            PartyPlan(
                roster: roster ?? party,
                equippedByMember: equippedByMember,
                gearAssignmentOverrides: gearAssignmentOverrides,
                plannedSlotOverrides: plannedSlotOverrides,
                gearTarget: gearTarget
            )
        }
        set {
            roster = newValue.roster
            equippedByMember = newValue.equippedByMember
            gearAssignmentOverrides = newValue.gearAssignmentOverrides
            plannedSlotOverrides = newValue.plannedSlotOverrides
            gearTarget = newValue.gearTarget
            syncActivePartyProjection()
        }
    }

    /// Fork a clean run while carrying forward only reusable character and
    /// build choices. All route, story, level, ability, and equipment state
    /// comes from the fresh HonorRun defaults.
    func freshRun(
        name: String,
        guideVersion: String,
        availableBuilds: [BuildSummary],
        createdAt: Date = .now
    ) -> HonorRun {
        var source = self
        source.normalizeRoster()

        var fresh = HonorRun()
        fresh.normalizeRoster()
        fresh.name = name
        fresh.createdAt = createdAt
        fresh.guideVersion = guideVersion

        let buildsByID = Dictionary(uniqueKeysWithValues: availableBuilds.map { ($0.id, $0) })
        let defaultMembers = Dictionary(uniqueKeysWithValues: (fresh.roster ?? fresh.party).map { ($0.id, $0) })
        fresh.roster = (source.roster ?? source.party).map { member in
            let build = member.buildId.flatMap { buildsByID[$0] }
            let defaultMember = defaultMembers[member.id]
            let status: RosterStatus
            switch member.rosterStatus {
            case .active, .camp, .unrecruited:
                status = member.rosterStatus
            case .unavailable, .dead, .departed:
                status = defaultMember?.rosterStatus ?? .camp
            }
            let className = build?.abilitySetups?
                .min(by: { $0.level < $1.level })?.firstClass
                ?? build?.levels.min(by: { $0.level < $1.level })?.take
                ?? defaultMember?.className
                ?? member.className
            return PartyMember(
                id: member.id,
                name: member.name,
                level: 1,
                buildId: build?.id,
                preparedTags: [],
                className: className,
                status: status,
                roleOverride: member.roleOverride,
                isCustom: member.isCustom,
                abilityScores: build?.startingAbilityScores
                    ?? (member.isCustom == true ? .customDefault : .forClass(className)),
                isHireling: member.isHireling,
                sourceLoadoutId: nil,
                abilityModifiers: [],
                usesBuildAbilityScores: build != nil,
                appliedAbilitySetupId: nil
            )
        }
        fresh.syncActivePartyProjection()
        return fresh
    }
}

struct PartyUndoState {
    let runID: String
    let message: String
    let plan: PartyPlan
}

struct CheckpointProgress: Codable, Hashable {
    var checkedPreparation: Set<String> = []
    var checkedCompletion: Set<String> = []
    var skipNote = ""
    var updatedAt = Date()
}

enum ActGearReviewStatus: String, Codable, CaseIterable, Identifiable {
    case obtained
    case missed

    var id: String { rawValue }
}

struct ActTransitionRecord: Codable, Hashable, Identifiable {
    var id: String { "\(fromAct)-\(toAct)" }
    let fromAct: Int
    let toAct: Int
    let gearReview: [String: ActGearReviewStatus]
    var gear: [BuildGear]? = nil
    let unresolvedRouteCount: Int
    let advancedAt: Date
}

struct HonorRun: Codable {
    var id = UUID().uuidString
    var name: String?
    var createdAt: Date?
    var guideVersion = ""
    var party: [PartyMember] = [
        PartyMember(id: "tav", name: "Tav", level: 1, buildId: nil, preparedTags: [], className: nil),
        PartyMember(id: "companion-1", name: "Shadowheart", level: 1, buildId: nil, preparedTags: [], className: "Cleric"),
        PartyMember(id: "companion-2", name: "Lae'zel", level: 1, buildId: nil, preparedTags: [], className: "Fighter"),
        PartyMember(id: "companion-3", name: "Astarion", level: 1, buildId: nil, preparedTags: [], className: "Rogue"),
    ]
    var roster: [PartyMember]?
    var storyOutcomes: Set<String> = []
    var includeCampPlans = false
    var equippedByMember: [String: Set<String>] = [:]
    var equipmentOwnershipKnown = false
    // Deterministic gear assignment: the player's manual item → member
    // overrides, and per-slot catalog swaps replacing a build's pick.
    var gearAssignmentOverrides: [String: String] = [:]
    var plannedSlotOverrides: [String: [String: String]] = [:]
    var progress: [String: CheckpointProgress] = [:]
    var walkthroughProgress: [String: CheckpointDisposition] = [:]
    // step id → the decision option that actually happened in this run
    var walkthroughOutcomes: [String: String] = [:]
    // Player-owned focus is deliberately separate from the assistant's route
    // recommendation. Open-world runs are allowed to diverge without losing
    // the recommended sequence.
    var focusedWalkthroughStepId: String?
    // Player-chosen equipment goal; shown on the Now page instead of the
    // route goal until acquired or cleared. Optional so old snapshots decode.
    var gearTarget: GearTarget?
    var selectedCheckpointId: String?
    var selectedAct = 1
    var actGearReview: [Int: [String: ActGearReviewStatus]] = [:]
    var actTransitions: [ActTransitionRecord] = []
    var finalActRecord: ActTransitionRecord?
    var mapRegion = "Wilderness"
    var mutedCheckpointIds: Set<String> = []

    /// Roster invariant enforcement and seeding: a fresh run (roster nil)
    /// gets its full roster built from the default party plus every story
    /// companion; existing rosters get nil fields seeded and the 4-active
    /// cap enforced. Idempotent — safe to call on every load.
    mutating func normalizeRoster() {
        if !(1...3).contains(selectedAct) { selectedAct = 1 }
        var members = roster ?? party
        for index in members.indices {
            if roster == nil { members[index].status = .active }
            if members[index].isCustom == nil {
                members[index].isCustom = members[index].id == "tav" || index == 0
            }
            if members[index].abilityScores == nil {
                members[index].abilityScores = members[index].isCustom == true
                    ? .customDefault
                    : .forClass(members[index].className)
            }
            if members[index].isHireling == nil { members[index].isHireling = false }
        }
        let existingNames = Set(members.map { $0.name.lowercased() })
        let recruitableNames = Set(StoryCompanion.recruitable.map { $0.name.lowercased() })
        for companion in StoryCompanion.all where !existingNames.contains(companion.name.lowercased()) {
            let stableID = companion.name.lowercased()
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: " ", with: "-")
            members.append(PartyMember(
                id: stableID,
                name: companion.name,
                level: party.map(\.level).max() ?? 1,
                buildId: nil,
                preparedTags: [],
                className: companion.defaultClass,
                status: recruitableNames.contains(companion.name.lowercased()) ? .unrecruited : .camp,
                roleOverride: nil,
                isCustom: false
            ))
        }
        var activeCount = 0
        for index in members.indices where members[index].rosterStatus == .active {
            activeCount += 1
            if activeCount > 4 { members[index].status = .camp }
        }
        roster = members
        syncActivePartyProjection()
        if storyOutcomes == nil { storyOutcomes = [] }
        if includeCampPlans == nil { includeCampPlans = false }
        if equippedByMember == nil { equippedByMember = [:] }
        if gearAssignmentOverrides == nil { gearAssignmentOverrides = [:] }
        if plannedSlotOverrides == nil { plannedSlotOverrides = [:] }
        if equipmentOwnershipKnown == nil { equipmentOwnershipKnown = false }
        if actGearReview == nil { actGearReview = [:] }
        if actTransitions == nil { actTransitions = [] }
    }

    var activeParty: [PartyMember] {
        (roster ?? party).filter { $0.rosterStatus == .active }.prefix(4).map { $0 }
    }

    mutating func syncActivePartyProjection() {
        party = activeParty
    }

    @discardableResult
    mutating func applyRosterStatus(_ status: RosterStatus, memberID: String) -> Bool {
        guard let index = roster?.firstIndex(where: { $0.id == memberID }) else { return false }
        let current = roster![index].rosterStatus
        if status == .active {
            guard current.canBeActive else { return false }
            let activeExcludingMember = roster!.filter { $0.id != memberID && $0.rosterStatus == .active }.count
            guard activeExcludingMember < 4 else { return false }
        }
        roster![index].status = status
        syncActivePartyProjection()
        return true
    }

    func equipmentOwnerID(for itemKey: String) -> String? {
        equippedByMember.first(where: { $0.value.contains(itemKey) })?.key
    }

    func actLedgerIsLocked(_ act: Int) -> Bool {
        act < selectedAct || (act == 3 && finalActRecord != nil)
    }

    func lockedActRecord(for act: Int) -> ActTransitionRecord? {
        guard actLedgerIsLocked(act) else { return nil }
        return act == 3
            ? finalActRecord
            : actTransitions.first(where: { $0.fromAct == act })
    }

    func lockedActGearReviewStatus(for itemKey: String, in act: Int) -> ActGearReviewStatus? {
        lockedActRecord(for: act)?.gearReview[itemKey]
    }

    @discardableResult
    mutating func toggleEquipment(itemKey: String, for memberID: String) -> Bool {
        guard (roster ?? party).contains(where: { $0.id == memberID }) else { return false }
        var assignments = equippedByMember
        let alreadyAssigned = assignments[memberID]?.contains(itemKey) == true
        for ownerID in Array(assignments.keys) {
            assignments[ownerID]?.remove(itemKey)
            if assignments[ownerID]?.isEmpty == true { assignments.removeValue(forKey: ownerID) }
        }
        if !alreadyAssigned { assignments[memberID, default: []].insert(itemKey) }
        equippedByMember = assignments
        equipmentOwnershipKnown = true
        return true
    }

    mutating func setStoryOutcome(_ outcome: String, confirmed: Bool) {
        var outcomes = storyOutcomes
        if confirmed { outcomes.insert(outcome) }
        else { outcomes.remove(outcome) }
        storyOutcomes = outcomes
    }
}

struct PendingRosterStatusChange: Identifiable {
    let memberID: String
    let memberName: String
    let target: RosterStatus
    let message: String
    var id: String { "\(memberID)-\(target.rawValue)" }
}

struct RoutePayload: Codable {
    let guideVersion: String
    let act: Int
    let routeAvailable: Bool
    let checkpoints: [RouteCheckpoint]
    let builds: [BuildSummary]
    let walkthrough: [WalkthroughStep]
    let timedEvents: [TimedEvent]
    let acts: [ActGuideSummary]
}

struct TimedEvent: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let trigger: String
    let deadline: String
    let consequence: String
    let severity: String
    let source: String
}

struct ActGuideSummary: Codable, Identifiable, Hashable {
    var id: Int { act }
    let act: Int
    let title: String
    let routeAvailable: Bool
    let localMapAvailable: Bool
    let mapName: String
    let mapUrl: String
    let equipmentFile: String
    let coordinateSystem: String
    let coordinateNote: String
    let equipmentCount: Int
}

enum ActMapHandoff: Equatable {
    case local
    case external(URL)
}

extension ActGuideSummary {
    var mapHandoff: ActMapHandoff? {
        if localMapAvailable { return .local }
        guard let url = URL(string: mapUrl) else { return nil }
        return .external(url)
    }
}

struct BackendHealth: Codable, Equatable {
    let ok: Bool
    let service: String
    let pid: Int32?
    let parentPid: Int32?
    let packaged: Bool?
    let walkthroughCount: Int?
    /// Server-side AI features (chat, build import) are usable. The provider
    /// key remains on that server; older backends omit the field.
    let aiAvailable: Bool?
    let authenticated: Bool?
    let buildImports: BuildImportQuota?
    let backendMode: String?
}

struct ReadinessResponse: Codable {
    let status: String
    let partyLevel: Int
    let minimumLevel: Int
    let blockers: [String]
    let warnings: [String]
    let nextActions: [String]
}

enum ChatScope: String, Codable, CaseIterable, Identifiable {
    case current
    case route
    case party

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ChatContextSnapshot: Codable {
    let version: Int
    let scope: ChatScope
    let guideVersion: String
    let selectedAct: Int
    let mapRegion: String
    let routePhase: String
    let recommendedStepId: String?
    let focusedStepId: String?
    let walkthroughStatuses: [String: String]
    let walkthroughOutcomes: [String: String]
    let roster: [PartyMember]
    let storyOutcomes: [String]
    let equippedByMember: [String: [String]]
    let equipmentOwnershipKnown: Bool
}

struct ChatTurn: Codable {
    let role: String  // "user" | "assistant"
    let content: String
}

struct ChatSource: Codable, Identifiable, Hashable {
    var id: String { url }
    let title: String
    let url: String
    let snippet: String?
    let image: String?
}

struct ChatRequest: Codable {
    let message: String
    let checkpointId: String?
    let party: [PartyMember]
    let completedCheckpointIds: [String]
    let skippedCheckpointIds: [String]
    let checkedPreparation: [String]
    let walkthroughStepId: String?
    var imageBase64: String? = nil  // optional BG3 screenshot for the vision model
    let context: ChatContextSnapshot
    var history: [ChatTurn] = []  // prior turns, oldest first
}

struct ChatResponse: Codable {
    let answer: String
    let guideFacts: [String]
    let assistantSuggestions: [String]
    let unknowns: [String]
    let sources: [ChatSource]  // backend always sends it; app and backend ship together
}

enum PlannerTab: String, CaseIterable, Identifiable {
    case current = "Now"
    case route = "Route"
    case party = "Party"
    case loadout = "Loadout"
    case act = "Act"
    case chat = "Chat"
    case settings = "Settings"
    var id: String { rawValue }

    static let primary: [PlannerTab] = [.current, .route, .party, .loadout, .act]
}

enum OverlayDensity: String, CaseIterable, Identifiable {
    case minimal = "Minimal"
    case focus = "Focus"
    case reference = "Reference"
    var id: String { rawValue }
}

enum AssistantPhase: String {
    case explore = "EXPLORE"
    case preflight = "PREFLIGHT"
    case dialogue = "DIALOGUE"
    case combat = "COMBAT"
    case levelUp = "LEVEL UP"
}
