import Foundation

enum CheckpointDisposition: String, Codable, CaseIterable {
    case pending
    case completed
    case skipped
}

struct GuideSource: Codable, Hashable {
    let sheet: String
    let row: Int
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
    let x: Int
    let y: Int
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
    var icon: String? = nil  // path under the local backend, e.g. /map-assets/icons/x.webp

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

struct BuildSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let honorStatus: String
    let role: String
    let finalSplit: String
    let classProgression: String
    let startingAbilities: String
    let playPattern: String
    let caveat: String
    let source: String
    let levels: [BuildLevel]
    let gear: [BuildGear]
}

struct StoryCompanion: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let defaultClass: String

    static let actOne = [
        StoryCompanion(name: "Shadowheart", defaultClass: "Cleric"),
        StoryCompanion(name: "Lae'zel", defaultClass: "Fighter"),
        StoryCompanion(name: "Astarion", defaultClass: "Rogue"),
        StoryCompanion(name: "Gale", defaultClass: "Wizard"),
        StoryCompanion(name: "Wyll", defaultClass: "Warlock"),
        StoryCompanion(name: "Karlach", defaultClass: "Barbarian"),
    ]
}

enum RosterStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case camp
    case unrecruited
    case unavailable
    case dead
    case departed

    var id: String { rawValue }
    var canBeActive: Bool { self == .active || self == .camp }
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

    var rosterStatus: RosterStatus { status ?? .active }
}

struct CheckpointProgress: Codable, Hashable {
    // disposition here is legacy — the walkthrough ledger is the source of
    // truth; only read during migrateLegacyFightDispositions.
    var disposition: CheckpointDisposition = .pending
    var checkedPreparation: Set<String> = []
    var checkedCompletion: Set<String> = []
    var skipNote = ""
    var updatedAt = Date()
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
    var storyOutcomes: Set<String>?
    var includeCampPlans: Bool?
    var equippedByMember: [String: Set<String>]?
    var equipmentOwnershipKnown: Bool?
    var progress: [String: CheckpointProgress] = [:]
    var walkthroughProgress: [String: CheckpointDisposition]?
    // step id → the decision option that actually happened in this run
    var walkthroughOutcomes: [String: String]?
    // Player-owned focus is deliberately separate from the assistant's route
    // recommendation. Open-world runs are allowed to diverge without losing
    // the recommended sequence.
    var focusedWalkthroughStepId: String?
    var selectedCheckpointId: String?
    var selectedAct: Int? = 1
    var mapRegion = "Wilderness"
    var mutedCheckpointIds: Set<String>?

    /// One-time migration: older runs kept fight dispositions in `progress`;
    /// copy any non-pending legacy disposition into the walkthrough ledger
    /// unless the ledger already has an entry. Idempotent.
    mutating func migrateLegacyFightDispositions(walkthrough: [WalkthroughStep]) {
        var ledger = walkthroughProgress ?? [:]
        for step in walkthrough {
            guard ledger[step.id] == nil,
                  let checkpointId = step.checkpointId,
                  let legacy = progress[checkpointId]?.disposition,
                  legacy != .pending else { continue }
            ledger[step.id] = legacy
        }
        walkthroughProgress = ledger
    }

    mutating func migrateLegacyPartySlots() {
        if !(1...3).contains(selectedAct ?? 0) { selectedAct = 1 }
        let defaults = HonorRun().party
        while party.count < defaults.count { party.append(defaults[party.count]) }
        if party.count > defaults.count { party = Array(party.prefix(defaults.count)) }
        for index in 1..<party.count where party[index].name == "Companion \(index)" || party[index].name.isEmpty {
            party[index].name = defaults[index].name
            if party[index].buildId == nil { party[index].className = defaults[index].className }
        }

        var members = roster ?? party
        for index in members.indices {
            if roster == nil { members[index].status = .active }
            if members[index].isCustom == nil {
                members[index].isCustom = members[index].id == "tav" || index == 0
            }
        }
        let existingNames = Set(members.map { $0.name.lowercased() })
        for companion in StoryCompanion.actOne where !existingNames.contains(companion.name.lowercased()) {
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
                status: .camp,
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
        if equipmentOwnershipKnown == nil { equipmentOwnershipKnown = false }
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
        equippedByMember?.first(where: { $0.value.contains(itemKey) })?.key
    }

    @discardableResult
    mutating func toggleEquipment(itemKey: String, for memberID: String) -> Bool {
        guard (roster ?? party).contains(where: { $0.id == memberID }) else { return false }
        var assignments = equippedByMember ?? [:]
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
        var outcomes = storyOutcomes ?? []
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
    let checkpoints: [RouteCheckpoint]
    let builds: [BuildSummary]
    let walkthrough: [WalkthroughStep]
}

struct BackendHealth: Codable, Equatable {
    let ok: Bool
    let service: String
    let pid: Int32?
    let parentPid: Int32?
    let packaged: Bool?
    let walkthroughCount: Int?
}

struct ReadinessRequest: Codable {
    let checkpointId: String
    let party: [PartyMember]
    let completedCheckpointIds: [String]
    let checkedPreparation: [String]
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
    let checkpointId: String
    let party: [PartyMember]
    let completedCheckpointIds: [String]
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
    case route = "Run"
    case party = "Party"
    case chat = "Chat"
    var id: String { rawValue }

    static let primary: [PlannerTab] = [.current, .route, .party]
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

enum RunSafety {
    static func walkthroughDisposition(
        _ step: WalkthroughStep,
        walkthroughProgress: [String: CheckpointDisposition]
    ) -> CheckpointDisposition {
        walkthroughProgress[step.id] ?? .pending
    }

    static func nextWalkthroughStep(
        walkthrough: [WalkthroughStep],
        walkthroughProgress: [String: CheckpointDisposition],
        selectedCheckpointId _: String?,
        walkthroughOutcomes: [String: String] = [:],
        partyLevel: Int
    ) -> WalkthroughStep? {
        let disposition: (WalkthroughStep) -> CheckpointDisposition = { step in
            walkthroughDisposition(step, walkthroughProgress: walkthroughProgress)
        }
        let pending = walkthrough.filter { disposition($0) == .pending }
        guard let phase = pending.map(\.phaseOrder).min() else { return nil }
        let phasePending = pending.filter { $0.phaseOrder == phase }.sorted { $0.order < $1.order }
        let eligible = phasePending.filter {
            dependencyBlockers(
                for: $0,
                walkthrough: walkthrough,
                walkthroughProgress: walkthroughProgress,
                walkthroughOutcomes: walkthroughOutcomes
            ).isEmpty
        }
        guard !eligible.isEmpty else { return nil }
        return eligible.first(where: { $0.minimumLevel <= partyLevel }) ?? eligible.first
    }

    static func dependencyBlockers(
        for step: WalkthroughStep,
        walkthrough: [WalkthroughStep],
        walkthroughProgress: [String: CheckpointDisposition],
        walkthroughOutcomes: [String: String] = [:]
    ) -> [String] {
        let titles = Dictionary(uniqueKeysWithValues: walkthrough.map { ($0.id, $0.title) })
        return step.dependencies.compactMap { dependency in
            let status = walkthroughProgress[dependency.stepId] ?? .pending
            let satisfied: Bool
            switch dependency.kind {
            case "warning_only":
                satisfied = true
            case "completion_required":
                satisfied = status == .completed
            case "outcome_required":
                satisfied = status == .completed
                    && walkthroughOutcomes[dependency.stepId] == dependency.requiredOutcome
            default:
                satisfied = status != .pending
            }
            guard !satisfied else { return nil }
            if status == .skipped,
               dependency.kind == "completion_required" || dependency.kind == "outcome_required" {
                return "Revisit \(titles[dependency.stepId] ?? dependency.stepId) — \(dependency.reason)"
            }
            return dependency.reason
        }
    }

    static func nextDialogueStep(
        walkthrough: [WalkthroughStep],
        walkthroughProgress: [String: CheckpointDisposition],
        selectedCheckpointId: String?,
        partyLevel: Int
    ) -> WalkthroughStep? {
        let current = nextWalkthroughStep(
            walkthrough: walkthrough,
            walkthroughProgress: walkthroughProgress,
            selectedCheckpointId: selectedCheckpointId,
            walkthroughOutcomes: [:],
            partyLevel: partyLevel
        )
        if let current, current.kind == "dialogue" || current.kind == "decision" { return current }
        let currentOrder = current?.order ?? 0
        let disposition: (WalkthroughStep) -> CheckpointDisposition = { step in
            walkthroughDisposition(step, walkthroughProgress: walkthroughProgress)
        }
        return walkthrough
            .filter {
                ($0.kind == "dialogue" || $0.kind == "decision")
                    && disposition($0) == .pending
                    && $0.order >= currentOrder
            }
            .sorted { $0.order < $1.order }
            .first
    }

    static func nextCheckpoint(
        route: [RouteCheckpoint],
        dispositions: [String: CheckpointDisposition],
        selectedId: String?,
        partyLevel: Int
    ) -> RouteCheckpoint? {
        if let selectedId, let selected = route.first(where: { $0.id == selectedId }) { return selected }
        let pending = route.filter { (dispositions[$0.id] ?? .pending) == .pending }
        guard let phase = pending.map(routePhase).min() else { return nil }
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(dispositions.compactMap { $0.value != .pending ? $0.key : nil })
        let eligible = phasePending.filter { checkpoint in
            checkpoint.prerequisites.allSatisfy { resolved.contains($0) }
        }
        let candidates = eligible.isEmpty ? phasePending : eligible
        let atOrBelowLevel = candidates.filter { $0.minimumLevel <= partyLevel }
        return (atOrBelowLevel.isEmpty ? candidates : atOrBelowLevel).min { lhs, rhs in
            let lhsDistance = abs(lhs.minimumLevel - partyLevel)
            let rhsDistance = abs(rhs.minimumLevel - partyLevel)
            return lhsDistance == rhsDistance ? lhs.routeOrder < rhs.routeOrder : lhsDistance < rhsDistance
        }
    }

    static func activityPlan(
        route: [RouteCheckpoint],
        dispositions: [String: CheckpointDisposition],
        selectedId: String?,
        partyLevel: Int
    ) -> LevelActivityPlan? {
        guard let recommendation = nextCheckpoint(
            route: route, dispositions: dispositions, selectedId: selectedId, partyLevel: partyLevel
        ) else { return nil }
        let pending = route.filter { (dispositions[$0.id] ?? .pending) == .pending }
        let phase = routePhase(recommendation)
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(dispositions.compactMap { $0.value != .pending ? $0.key : nil })
        let eligible = phasePending.filter { checkpoint in
            checkpoint.prerequisites.allSatisfy { resolved.contains($0) }
        }
        let safeXP = eligible
            .filter { $0.importance == "minor" && $0.minimumLevel <= partyLevel }
            .sorted { $0.routeOrder < $1.routeOrder }
        let major = phasePending
            .filter { $0.importance == "major" }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.minimumLevel - partyLevel)
                let rhsDistance = abs(rhs.minimumLevel - partyLevel)
                return lhsDistance == rhsDistance ? lhs.routeOrder < rhs.routeOrder : lhsDistance < rhsDistance
            }
        let activityLabel: String
        let gateAdvice: String
        if recommendation.minimumLevel > partyLevel {
            activityLabel = "EARN XP FIRST"
            gateAdvice = "This needs L\(recommendation.minimumLevel). Do quests and the safe fights in \(routePhaseName(recommendation)), then come back."
        } else if recommendation.importance == "major" {
            activityLabel = "MAIN FIGHT"
            gateAdvice = "You're at level. Run the prep list, then start it on your terms."
        } else {
            activityLabel = "SAFE XP"
            if let major, major.minimumLevel > partyLevel {
                gateAdvice = "Safe at your level — builds XP toward \(major.name) (L\(major.minimumLevel))."
            } else {
                gateAdvice = "Safe at your level. Clear it before the main fight."
            }
        }
        return LevelActivityPlan(
            activityLabel: activityLabel,
            phaseName: routePhaseName(recommendation),
            recommendation: recommendation,
            safeXP: safeXP,
            coreChallenge: major,
            gateAdvice: gateAdvice
        )
    }

    static func routePhase(_ checkpoint: RouteCheckpoint) -> Int {
        switch checkpoint.region {
        case "Nautiloid": return 0
        case "Underdark": return 2
        case "Grymforge": return 3
        case "Crèche Y'llek": return 4
        default: return 1
        }
    }

    static func routePhaseName(_ checkpoint: RouteCheckpoint) -> String {
        switch routePhase(checkpoint) {
        case 0: return "Nautiloid"
        case 1: return "Wilderness cleanup"
        case 2: return "Underdark"
        case 3: return "Grymforge"
        default: return "Mountain Pass / Crèche"
        }
    }

    static func completionConfirmationReasons(
        checkpoint: RouteCheckpoint,
        progress: CheckpointProgress,
        readinessStatus: String?
    ) -> [String] {
        var reasons: [String] = []
        if readinessStatus == "blocked" { reasons.append("readiness is blocked") }
        let missing = checkpoint.completionChecks.filter { !progress.checkedCompletion.contains($0) }
        if !missing.isEmpty { reasons.append("\(missing.count) completion check(s) are unconfirmed") }
        if !checkpoint.irreversibleWarnings.isEmpty {
            reasons.append("this checkpoint has irreversible or time-sensitive consequences")
        }
        return reasons
    }

    static func actTwoBlockers(route: [RouteCheckpoint], dispositions: [String: CheckpointDisposition]) -> [String] {
        route.compactMap { checkpoint in
            let state = dispositions[checkpoint.id] ?? .pending
            guard state != .completed, checkpoint.importance == "major" || !checkpoint.irreversibleWarnings.isEmpty else { return nil }
            let prefix = state == .skipped ? "Skipped" : "Unresolved"
            return "\(prefix) — \(checkpoint.name): \(checkpoint.irreversibleWarnings.first ?? "major checkpoint unresolved")"
        }
    }
}
