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

struct PartyMember: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var level: Int
    var buildId: String?
    var preparedTags: [String]
    var className: String?
}

struct CheckpointProgress: Codable, Hashable {
    var disposition: CheckpointDisposition = .pending
    var checkedPreparation: Set<String> = []
    var checkedCompletion: Set<String> = []
    var skipNote = ""
    var updatedAt = Date()
}

struct HonorRun: Codable {
    var id = UUID().uuidString
    var guideVersion = ""
    var party: [PartyMember] = [
        PartyMember(id: "tav", name: "Tav", level: 1, buildId: nil, preparedTags: [], className: nil),
        PartyMember(id: "companion-1", name: "Shadowheart", level: 1, buildId: nil, preparedTags: [], className: "Cleric"),
        PartyMember(id: "companion-2", name: "Lae'zel", level: 1, buildId: nil, preparedTags: [], className: "Fighter"),
        PartyMember(id: "companion-3", name: "Astarion", level: 1, buildId: nil, preparedTags: [], className: "Rogue"),
    ]
    var progress: [String: CheckpointProgress] = [:]
    var selectedCheckpointId: String?
    var selectedAct: Int? = 1
    var mapRegion = "Wilderness"
    var mutedCheckpointIds: Set<String>?

    mutating func migrateLegacyPartySlots() {
        if !(1...3).contains(selectedAct ?? 0) { selectedAct = 1 }
        let defaults = HonorRun().party
        while party.count < defaults.count { party.append(defaults[party.count]) }
        if party.count > defaults.count { party = Array(party.prefix(defaults.count)) }
        for index in 1..<party.count where party[index].name == "Companion \(index)" || party[index].name.isEmpty {
            party[index].name = defaults[index].name
            if party[index].buildId == nil { party[index].className = defaults[index].className }
        }
    }
}

struct RoutePayload: Codable {
    let guideVersion: String
    let checkpoints: [RouteCheckpoint]
    let builds: [BuildSummary]
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

struct ChatRequest: Codable {
    let message: String
    let checkpointId: String
    let party: [PartyMember]
    let completedCheckpointIds: [String]
    let screenshotContext: String?
}

struct ChatResponse: Codable {
    let answer: String
    let guideFacts: [String]
    let assistantSuggestions: [String]
    let unknowns: [String]
}

struct ScreenDetected: Codable {
    let game: String
    let likelyArea: String
    let screenKind: String
    let visibleEnemies: [String]
    let visibleParty: [String]
    let visibleLevels: [Int]
    let dialogueOrWarning: String
    let evidence: [String]
}

struct ScreenCandidate: Codable, Identifiable {
    var id: String { checkpointId }
    let checkpointId: String
    let confidence: Double
    let reason: String
}

struct AnalysisResponse: Codable {
    let ok: Bool
    let analysisId: String
    let screenSummary: String
    let detected: ScreenDetected
    let candidates: [ScreenCandidate]
    let confidence: Double
    let latencyMs: Int
    let error: String?
}

struct MapAlignContext: Codable {
    let checkpointId: String?
    let completedCheckpointIds: [String]
    let useActiveMarkerSync: Bool
}

struct MapAlignLatLng: Codable {
    let lat: Double
    let lng: Double
}

struct MapAlignTarget: Codable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let danger: String
    let lat: Double
    let lng: Double
    let x: Double
    let y: Double
    let onScreen: Bool
}

struct MapAlignResponse: Codable {
    let ok: Bool
    let mapOpen: Bool
    let inliers: Int
    let confidence: Double
    let zoom: Double?
    let center: MapAlignLatLng?
    let positionUpdated: Bool
    let targets: [MapAlignTarget]
    let latencyMs: Int
    let error: String?
}

enum PlannerTab: String, CaseIterable, Identifiable {
    case current = "Current"
    case route = "Route"
    case party = "Party"
    case chat = "Chat"
    var id: String { rawValue }
}

enum RunSafety {
    static func nextCheckpoint(
        route: [RouteCheckpoint],
        progress: [String: CheckpointProgress],
        selectedId: String?,
        partyLevel: Int
    ) -> RouteCheckpoint? {
        if let selectedId, let selected = route.first(where: { $0.id == selectedId }) { return selected }
        let pending = route.filter { (progress[$0.id]?.disposition ?? .pending) == .pending }
        guard let phase = pending.map(routePhase).min() else { return nil }
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(progress.compactMap { $0.value.disposition != .pending ? $0.key : nil })
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
        progress: [String: CheckpointProgress],
        selectedId: String?,
        partyLevel: Int
    ) -> LevelActivityPlan? {
        guard let recommendation = nextCheckpoint(
            route: route, progress: progress, selectedId: selectedId, partyLevel: partyLevel
        ) else { return nil }
        let pending = route.filter { (progress[$0.id]?.disposition ?? .pending) == .pending }
        let phase = routePhase(recommendation)
        let phasePending = pending.filter { routePhase($0) == phase }
        let resolved = Set(progress.compactMap { $0.value.disposition != .pending ? $0.key : nil })
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

    static func actTwoBlockers(route: [RouteCheckpoint], progress: [String: CheckpointProgress]) -> [String] {
        route.compactMap { checkpoint in
            let state = progress[checkpoint.id]?.disposition ?? .pending
            guard state != .completed, checkpoint.importance == "major" || !checkpoint.irreversibleWarnings.isEmpty else { return nil }
            let prefix = state == .skipped ? "Skipped" : "Unresolved"
            return "\(prefix) — \(checkpoint.name): \(checkpoint.irreversibleWarnings.first ?? "major checkpoint unresolved")"
        }
    }
}
