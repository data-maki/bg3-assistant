import Foundation

enum Ability: String, Codable, CaseIterable, Identifiable {
    case strength
    case dexterity
    case constitution
    case intelligence
    case wisdom
    case charisma

    var id: String { rawValue }
    var shortName: String { String(rawValue.prefix(3)).uppercased() }
    var displayName: String { rawValue.capitalized }

    func value(in scores: AbilityScores) -> Int {
        switch self {
        case .strength: scores.strength
        case .dexterity: scores.dexterity
        case .constitution: scores.constitution
        case .intelligence: scores.intelligence
        case .wisdom: scores.wisdom
        case .charisma: scores.charisma
        }
    }
}

enum AbilityModifierKind: String, Codable, CaseIterable {
    case permanent
    case temporary
    case equipment

    var label: String {
        switch self {
        case .permanent: "Permanent"
        case .temporary: "Temporary"
        case .equipment: "Equipment"
        }
    }
}

enum AbilityModifierMode: String, Codable {
    case add
    case minimum
}

struct AbilityModifier: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    let ability: Ability
    let kind: AbilityModifierKind
    let mode: AbilityModifierMode
    let value: Int
    let source: String
    var planSourceId: String? = nil
}

struct AbilityBreakdown {
    let ability: Ability
    let starting: Int
    let levelGain: Int
    let permanent: Int
    let equipment: Int
    let temporary: Int
    let current: Int
    let target: Int

    var normal: Int { starting + levelGain }

    var tooltip: String {
        var parts = ["\(starting) starting"]
        if levelGain > 0 { parts.append("+ \(levelGain) feat / ASI") }
        if permanent > 0 { parts.append("+ \(permanent) permanent") }
        if equipment > 0 { parts.append("+ \(equipment) equipment") }
        if temporary > 0 { parts.append("+ \(temporary) temporary") }
        let missing = max(0, target - current)
        let targetStatus = missing > 0
            ? "\(missing) planned before the build goal of \(target)."
            : current > target ? "\(current - target) above the build goal of \(target)." : "Build goal: \(target)."
        return "\(ability.displayName): \(parts.joined(separator: " ")) = \(current). \(targetStatus)"
    }
}

enum AbilityProgression {
    static func activeSetup(in build: BuildSummary?, at level: Int) -> AbilitySetupPlan? {
        build?.abilitySetups?.filter { $0.level <= level }.max { $0.level < $1.level }
    }

    static func pointBuyCost(_ scores: AbilityScores) -> Int {
        let costs = [8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9]
        let values = Ability.allCases.map { $0.value(in: scores) }
        guard values.allSatisfy({ costs[$0] != nil }) else { return -1 }
        return values.reduce(0) { $0 + costs[$1]! }
    }

    static func isValidBG3Setup(_ setup: AbilitySetupPlan) -> Bool {
        guard setup.bonusTwo != setup.bonusOne, pointBuyCost(setup.pointBuyScores) == 27 else { return false }
        return Ability.allCases.allSatisfy { ability in
            let bonus = ability == setup.bonusTwo ? 2 : ability == setup.bonusOne ? 1 : 0
            return ability.value(in: setup.finalScores) == ability.value(in: setup.pointBuyScores) + bonus
        }
    }

    static func modifier(for score: Int) -> Int {
        Int(floor(Double(score - 10) / 2.0))
    }

    static func breakdown(
        for member: PartyMember,
        build: BuildSummary?,
        ability: Ability,
        equippedItemKeys: Set<String> = []
    ) -> AbilityBreakdown {
        let currentLevels = build?.levels.filter { $0.level <= member.level } ?? []
        let activeSetup = activeSetup(in: build, at: member.level)
        let currentReset = activeSetup == nil ? currentLevels.last { $0.abilityScoreReset != nil } : nil
        let recommendedScores = activeSetup?.finalScores ?? currentReset?.abilityScoreReset ?? build?.startingAbilityScores
        // Recorded member scores remain authoritative until a new setup is
        // explicitly marked applied in BG3.
        let startingScores = member.abilityScores ?? recommendedScores ?? member.effectiveAbilityScores
        let starting = ability.value(in: startingScores)
        let structuredSources = build?.abilitySources ?? []
        let hasAppliedBuildSetup = member.appliedAbilitySetupId.map { appliedID in
            build?.abilitySetups?.contains { $0.id == appliedID } == true
        } ?? false
        let levelGain = structuredSources.isEmpty
            ? abilityGain(in: currentLevels.filter { $0.level > (currentReset?.level ?? 0) }, ability: ability)
            : hasAppliedBuildSetup
                ? sourceGain(in: structuredSources, ability: ability, level: member.level, kinds: [.asi, .feat])
                : 0
        let finalLevels = build?.levels ?? currentLevels
        let finalReset = finalLevels.last { $0.abilityScoreReset != nil }
        let finalStarting = ability.value(in: finalReset?.abilityScoreReset ?? startingScores)
        let finalGain = structuredSources.isEmpty
            ? abilityGain(in: finalLevels.filter { $0.level > (finalReset?.level ?? 0) }, ability: ability)
            : sourceGain(in: structuredSources, ability: ability, level: 12, kinds: [.asi, .feat])
        let modifiers = (member.abilityModifiers ?? []).filter { $0.ability == ability }

        var running = starting + levelGain
        let permanent = contribution(of: .permanent, modifiers: modifiers, running: &running)
        let beforeEquipment = running
        for source in structuredSources where source.ability == ability
            && source.kind == .equipment
            && source.applies(at: member.level)
            && source.itemKey.map(equippedItemKeys.contains) == true {
            apply(source.mode, value: source.value, running: &running)
        }
        _ = contribution(of: .equipment, modifiers: modifiers, running: &running)
        let equipment = running - beforeEquipment
        let temporary = contribution(of: .temporary, modifiers: modifiers, running: &running)
        let buildTarget = build?.targetAbilityScores.map { ability.value(in: $0) }
        let target = buildTarget ?? finalStarting + finalGain
        return AbilityBreakdown(
            ability: ability,
            starting: starting,
            levelGain: levelGain,
            permanent: permanent,
            equipment: equipment,
            temporary: temporary,
            current: running,
            target: target
        )
    }

    static func nextFeat(in build: BuildSummary?, after level: Int) -> BuildLevel? {
        build?.levels.first { step in
            step.level > level && isAbilityChoice(step.choices)
        }
    }

    private static func contribution(
        of kind: AbilityModifierKind,
        modifiers: [AbilityModifier],
        running: inout Int
    ) -> Int {
        let before = running
        for modifier in modifiers where modifier.kind == kind && modifier.mode == .add {
            running += modifier.value
        }
        for modifier in modifiers where modifier.kind == kind && modifier.mode == .minimum {
            running = max(running, modifier.value)
        }
        return running - before
    }

    private static func apply(_ mode: AbilityModifierMode, value: Int, running: inout Int) {
        switch mode {
        case .add: running += value
        case .minimum: running = max(running, value)
        }
    }

    private static func sourceGain(
        in sources: [AbilityPlanSource],
        ability: Ability,
        level: Int,
        kinds: Set<AbilityPlanSourceKind>
    ) -> Int {
        sources.reduce(0) { total, source in
            guard source.ability == ability, kinds.contains(source.kind), source.applies(at: level) else { return total }
            return source.mode == .add ? total + source.value : max(total, source.value)
        }
    }

    private static func abilityGain(in levels: [BuildLevel], ability: Ability) -> Int {
        levels.reduce(0) { total, level in
            total + explicitGain(in: level.choices, ability: ability)
        }
    }

    private static func explicitGain(in choices: String, ability: Ability) -> Int {
        let aliases = [ability.shortName, ability.displayName]
        var total = 0
        for alias in aliases {
            let patterns = [
                #"\+(\d+)\s*\#(alias)\b"#,
                #"\b\#(alias)\s*\+(\d+)\b"#,
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(choices.startIndex..., in: choices)
                for match in regex.matches(in: choices, range: range) where match.numberOfRanges > 1 {
                    if let valueRange = Range(match.range(at: 1), in: choices) {
                        total += Int(choices[valueRange]) ?? 0
                    }
                }
            }
        }
        let lower = choices.lowercased()
        if total == 0 {
            if ability == .wisdom && lower.contains("resilient: wisdom") { total = 1 }
            if ability == .charisma && lower.contains("actor") { total = 1 }
            if ability == .strength && lower.contains("heavy armour master") { total = 1 }
        }
        return total
    }

    private static func isAbilityChoice(_ choices: String) -> Bool {
        let lower = choices.lowercased()
        return lower.contains("asi")
            || lower.contains("ability improvement")
            || lower.contains("feat")
            || lower.contains("tavern brawler")
            || lower.contains("resilient:")
            || lower.contains("actor")
            || lower.contains("savage attacker")
            || lower.contains("sharpshooter")
            || lower.contains("dual wielder")
            || lower.contains("war caster")
            || lower.contains("alert")
            || lower.range(of: #"\+\d+\s+(str|dex|con|int|wis|cha)"#, options: .regularExpression) != nil
    }
}
