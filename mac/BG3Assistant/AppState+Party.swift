import Foundation

/// Who wears a build item that more than one active member wants.
struct GearConflict {
    let mine: Bool  // this character has the stronger claim
    let short: String
    let detail: String
}

/// Party, roster, and loadout editing: everything that mutates who is in the
/// run and what they carry. Route/overlay orchestration stays in AppState.
@MainActor
extension AppState {
    private func recordPartyUndo(_ message: String) {
        partyUndoState = PartyUndoState(runID: run.id, message: message, plan: run.partyPlan)
    }

    func undoLastPartyChange() {
        guard let undo = partyUndoState, undo.runID == run.id else {
            partyUndoState = nil
            return
        }
        run.partyPlan = undo.plan
        partyUndoState = nil
        persistRun()
        refreshReadiness()
    }

    @discardableResult
    func importBuild() async -> BuildSummary? {
        let url = loadoutURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            loadoutImportStatus = "Paste a public build URL first."
            return nil
        }
        guard buildImportAvailable else {
            loadoutImportStatus = "Choose and configure an AI provider in Settings first."
            return nil
        }
        guard !isImportingLoadout else { return nil }
        isImportingLoadout = true
        loadoutImportStatus = "Reading and processing the build…"
        defer { isImportingLoadout = false }
        do {
            guard let aiProvider else { throw AIProviderError.providerNotConfigured }
            let source = try await BuildImportSourceLoader.load(url)
            loadoutImportStatus = "Extracting classes, levels, abilities, and gear…"
            let content = try await assistantAIClient.completeJSON(
                provider: aiProvider,
                messages: [
                    AssistantAIMessage(role: "system", content: BuildImportPrompt.system),
                    AssistantAIMessage(
                        role: "user",
                        content: "SOURCE URL: \(source.url.absoluteString)\n\nBEGIN UNTRUSTED PAGE TEXT\n\(source.text)\nEND UNTRUSTED PAGE TEXT"
                    ),
                ],
                jsonSchema: BuildImportPrompt.schema,
                temperature: 0,
                maxTokens: 10_000,
                ollamaRuntime: ollamaRuntime
            )
            guard let data = content.data(using: .utf8) else { throw AIProviderError.invalidResponse }
            let imported = try JSONDecoder().decode(BuildImportDraft.self, from: data).importedBuild(sourceURL: source.url)
            try applyImportedBuild(imported)
            loadoutURLDraft = ""
            loadoutImportStatus = "Imported \(imported.name). Assign it to any character from Party."
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(imported) {
                loadoutImportJSON = String(data: data, encoding: .utf8)
            }
            return imported.build
        } catch {
            loadoutImportStatus = error.localizedDescription
            return nil
        }
    }

    func respec(_ member: PartyMember) {
        guard let index = run.roster?.firstIndex(where: { $0.id == member.id }) else { return }
        recordPartyUndo("Reset \(member.name)'s character plan")
        var reset = member
        let hireling = WithersHireling.matching(member.name)
        let companion = StoryCompanion.all.first { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }
        let defaultClass = hireling?.defaultClass ?? companion?.defaultClass ?? member.className
        reset.buildId = nil
        reset.className = member.isCustom == true ? nil : defaultClass
        reset.preparedTags = []
        reset.roleOverride = nil
        reset.abilityScores = member.isCustom == true ? .customDefault : .forClass(defaultClass)
        reset.abilityModifiers = []
        reset.usesBuildAbilityScores = false
        reset.appliedAbilitySetupId = nil
        reset.sourceLoadoutId = nil
        reset.manualBuild = nil
        run.roster?[index] = reset
        run.equippedByMember?[member.id] = nil
        run.buildAssignedAt?.removeValue(forKey: member.id)
        run.plannedSlotOverrides?.removeValue(forKey: member.id)
        run.gearAssignmentOverrides = run.gearAssignmentOverrides?.filter { $0.value != member.id }
        run.syncActivePartyProjection()
        validateGearTarget()
        persistRun()
        refreshReadiness()
    }

    @discardableResult
    func addHireling(_ hireling: WithersHireling) -> Bool {
        var members = run.roster ?? run.party
        guard !members.contains(where: { $0.name.caseInsensitiveCompare(hireling.name) == .orderedSame }) else {
            errorMessage = "\(hireling.name) is already in this run."
            return false
        }
        guard members.filter({ $0.isHireling == true }).count < 3 else {
            errorMessage = "Withers allows up to three hirelings in a run."
            return false
        }
        recordPartyUndo("Recorded \(hireling.name) as recruited")
        let member = PartyMember(
            id: "hireling-" + hireling.name.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-")),
            name: hireling.name,
            level: max(3, lowestPartyLevel),
            buildId: nil,
            preparedTags: [],
            className: hireling.defaultClass,
            status: .camp,
            roleOverride: nil,
            isCustom: false,
            abilityScores: hireling.defaultAbilityScores,
            isHireling: true
        )
        members.append(member)
        run.roster = members
        run.syncActivePartyProjection()
        persistRun()
        return true
    }

    @discardableResult
    func removeHireling(_ member: PartyMember) -> Bool {
        guard member.isHireling == true,
              var members = run.roster,
              let index = members.firstIndex(where: { $0.id == member.id }) else {
            errorMessage = "Could not find that hireling in this run."
            return false
        }
        guard member.rosterStatus != .active else {
            errorMessage = "Send \(member.name) to the inactive roster before replacing them."
            return false
        }
        recordPartyUndo("Dismissed \(member.name)")
        members.remove(at: index)
        run.roster = members
        run.equippedByMember?.removeValue(forKey: member.id)
        run.buildAssignedAt?.removeValue(forKey: member.id)
        run.plannedSlotOverrides?.removeValue(forKey: member.id)
        run.gearAssignmentOverrides = run.gearAssignmentOverrides?.filter { $0.value != member.id }
        run.syncActivePartyProjection()
        validateGearTarget()
        persistRun()
        refreshReadiness()
        return true
    }

    private func applyImportedBuild(_ imported: ImportedBuild) throws {
        builds.removeAll { $0.id == imported.build.id }
        builds.append(imported.build)
        try importedBuildStore.save(builds.filter { $0.id.hasPrefix("imported-") })
    }

    func migrateBuildAbilityScoresIfNeeded() {
        guard var members = run.roster else { return }
        var changed = false
        for index in members.indices where members[index].usesBuildAbilityScores == nil {
            if let buildID = members[index].buildId,
               let scores = builds.first(where: { $0.id == buildID })?.startingAbilityScores {
                members[index].abilityScores = scores
                members[index].usesBuildAbilityScores = true
            } else {
                members[index].usesBuildAbilityScores = false
            }
            if members[index].abilityModifiers == nil { members[index].abilityModifiers = [] }
            changed = true
        }
        guard changed else { return }
        run.roster = members
        run.syncActivePartyProjection()
        persistRun()
    }

    func updatePartyMember(_ member: PartyMember, preserveUndo: Bool = false) {
        guard let index = run.roster?.firstIndex(where: { $0.id == member.id }) else { return }
        if !preserveUndo { partyUndoState = nil }
        run.roster?[index] = member
        run.syncActivePartyProjection()
        validateGearTarget()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        refreshReadiness()
    }

    func updatePartyLevel(_ level: Int, for member: PartyMember) {
        var copy = member
        copy.level = level
        if let manual = copy.manualBuild, !manual.classSummary.isEmpty {
            copy.className = manual.classSummary
        } else if let build = builds.first(where: { $0.id == copy.buildId }),
           let plan = build.levels.last(where: { $0.level <= level }) {
            copy.className = plan.take
        }
        updatePartyMember(copy)
    }

    func beginManualBuild(for member: PartyMember) {
        guard member.manualBuild == nil else { return }
        var copy = member
        copy.buildId = nil
        var plan = ManualBuildPlan.empty(
            name: "\(member.name)'s Build",
            scores: member.effectiveAbilityScores.clampedForPointBuy
        )
        if let existingClass = member.className,
           let startingClass = BG3ClassCatalog.definitions.first(where: {
               existingClass == $0.name || existingClass.hasPrefix("\($0.name) ")
           })?.name {
            for index in plan.levels.indices {
                plan.levels[index].className = startingClass
            }
        }
        copy.manualBuild = plan
        copy.abilityScores = copy.manualBuild?.abilityScores
        copy.usesBuildAbilityScores = false
        run.buildAssignedAt?.removeValue(forKey: member.id)
        updatePartyMember(copy)
    }

    func renameManualBuild(_ name: String, for member: PartyMember) {
        var copy = member
        guard copy.manualBuild != nil else { return }
        copy.manualBuild?.name = name
        updatePartyMember(copy)
    }

    func setManualAbility(_ ability: Ability, value: Int, for member: PartyMember) {
        var copy = member
        guard copy.manualBuild != nil else { return }
        var scores = copy.manualBuild!.abilityScores
        switch ability {
        case .strength: scores.strength = value
        case .dexterity: scores.dexterity = value
        case .constitution: scores.constitution = value
        case .intelligence: scores.intelligence = value
        case .wisdom: scores.wisdom = value
        case .charisma: scores.charisma = value
        }
        copy.manualBuild?.abilityScores = scores
        copy.abilityScores = scores
        updatePartyMember(copy)
    }

    func setManualClass(_ className: String, at characterLevel: Int, for member: PartyMember) {
        var copy = member
        guard var plan = copy.manualBuild,
              plan.levels.contains(where: { $0.characterLevel == characterLevel }) else { return }
        if runDifficulty == .explorer,
           let firstClass = plan.levels.first?.className,
           !firstClass.isEmpty,
           !className.isEmpty,
           className != firstClass {
            errorMessage = "Explorer difficulty does not allow multiclassing."
            return
        }
        plan.setClass(className, at: characterLevel)
        copy.manualBuild = plan
        copy.buildId = nil
        copy.className = plan.classSummary.isEmpty ? nil : plan.classSummary
        copy.usesBuildAbilityScores = false
        updatePartyMember(copy)
    }

    func toggleManualChoice(
        _ option: String,
        in group: BG3BuildChoiceGroup,
        at characterLevel: Int,
        for member: PartyMember
    ) {
        var copy = member
        guard var plan = copy.manualBuild,
              let index = plan.levels.firstIndex(where: { $0.characterLevel == characterLevel }) else { return }
        var selected = plan.levels[index].selections[group.id] ?? []
        if let existing = selected.firstIndex(of: option) {
            selected.remove(at: existing)
        } else {
            if selected.count >= group.maximumSelections { selected.removeFirst() }
            selected.append(option)
        }
        plan.levels[index].selections[group.id] = selected
        copy.manualBuild = plan
        updatePartyMember(copy)
    }

    /// Replacing a build discards run-specific planning; confirm first when the
    /// member has anything to lose (tracked modifiers, equipped gear, applied setup).
    func buildReplacementNeedsConfirmation(for member: PartyMember) -> Bool {
        member.buildId != nil && (
            (member.abilityModifiers ?? []).contains { $0.kind != .permanent }
                || !equippedItemKeys(for: member).isEmpty
                || member.appliedAbilitySetupId != nil
        )
    }

    func assignBuild(_ buildID: String?, to member: PartyMember) {
        recordPartyUndo("Changed \(member.name)'s build")
        var copy = member
        copy.buildId = buildID
        if buildID != nil { copy.manualBuild = nil }
        copy.appliedAbilitySetupId = nil
        // "First to request" recency: stamp when a (different) build lands;
        // clearing the build also clears the stamp and any slot swaps.
        if buildID == nil {
            run.buildAssignedAt?.removeValue(forKey: member.id)
            run.plannedSlotOverrides?.removeValue(forKey: member.id)
        } else if buildID != member.buildId {
            run.buildAssignedAt = run.buildAssignedAt ?? [:]
            run.buildAssignedAt?[member.id] = Date()
            run.plannedSlotOverrides?.removeValue(forKey: member.id)
        }
        guard let buildID,
              let build = builds.first(where: { $0.id == buildID }) else {
            copy.abilityModifiers = (copy.abilityModifiers ?? []).filter { $0.kind == .permanent }
            copy.usesBuildAbilityScores = false
            updatePartyMember(copy, preserveUndo: true)
            return
        }
        if let plan = build.levels.last(where: { $0.level <= copy.level }) {
            copy.className = plan.take
        }
        // Keep the player's recorded in-game values until they explicitly
        // mark the new build recipe as applied.
        // Permanent rewards belong to the character, not the selected build.
        copy.abilityModifiers = (copy.abilityModifiers ?? []).filter { $0.kind == .permanent }
        copy.usesBuildAbilityScores = true
        updatePartyMember(copy, preserveUndo: true)
    }

    func applyAbilitySetup(_ setup: AbilitySetupPlan, to member: PartyMember) {
        recordPartyUndo("Recorded \(setup.label) for \(member.name)")
        var copy = member
        copy.abilityScores = setup.finalScores
        copy.usesBuildAbilityScores = true
        copy.appliedAbilitySetupId = setup.id
        updatePartyMember(copy, preserveUndo: true)
    }

    func equippedItemKeys(for member: PartyMember) -> Set<String> {
        Set(run.equippedByMember?[member.id] ?? [])
    }

    func abilitySourceIsApplied(_ source: AbilityPlanSource, to member: PartyMember) -> Bool {
        if source.kind == .equipment, let itemKey = source.itemKey {
            return equippedItemKeys(for: member).contains(itemKey)
        }
        return (member.abilityModifiers ?? []).contains {
            $0.planSourceId == source.id || ($0.planSourceId == nil && $0.source == source.label)
        }
    }

    func abilitySourceOwner(_ source: AbilityPlanSource) -> PartyMember? {
        guard source.uniqueAcrossParty else { return nil }
        if source.kind == .equipment, let itemKey = source.itemKey,
           let memberID = run.equippedByMember?.first(where: { $0.value.contains(itemKey) })?.key {
            return roster.first { $0.id == memberID }
        }
        return roster.first { member in
            (member.abilityModifiers ?? []).contains { $0.source == source.label }
        }
    }

    func setAbilitySource(_ source: AbilityPlanSource, applied: Bool, for member: PartyMember) {
        guard [.permanent, .consumable].contains(source.kind), var members = run.roster,
              let memberIndex = members.firstIndex(where: { $0.id == member.id }) else { return }
        guard !applied || (selectedAct >= source.minimumAct && member.level >= source.minimumLevel) else {
            errorMessage = "\(source.label) is planned for Act \(source.minimumAct), level \(source.minimumLevel) or later."
            return
        }
        recordPartyUndo("\(applied ? "Recorded" : "Removed") \(source.label) for \(member.name)")
        if source.uniqueAcrossParty, applied {
            for index in members.indices {
                members[index].abilityModifiers = (members[index].abilityModifiers ?? []).filter { $0.source != source.label }
            }
        }
        var modifiers = members[memberIndex].abilityModifiers ?? []
        modifiers.removeAll { $0.planSourceId == source.id || $0.source == source.label }
        if source.kind == .consumable, applied {
            modifiers.removeAll { $0.kind == .temporary }
        }
        if applied {
            modifiers.append(AbilityModifier(
                ability: source.ability,
                kind: source.kind == .permanent ? .permanent : .temporary,
                mode: source.mode,
                value: source.value,
                source: source.label,
                planSourceId: source.id
            ))
        }
        members[memberIndex].abilityModifiers = modifiers
        run.roster = members
        run.syncActivePartyProjection()
        persistRun()
        refreshReadiness()
    }

    @discardableResult
    func swapIntoActive(_ member: PartyMember, replacing activeMember: PartyMember) -> Bool {
        guard member.rosterStatus.canBeActive, member.rosterStatus != .active,
              activeMember.rosterStatus == .active,
              var members = run.roster,
              let incoming = members.firstIndex(where: { $0.id == member.id }),
              let outgoing = members.firstIndex(where: { $0.id == activeMember.id }) else {
            errorMessage = "Only a Camp or unrecruited member can replace an active party member."
            return false
        }
        recordPartyUndo("Swapped \(member.name) for \(activeMember.name)")
        var incomingMember = members[incoming]
        var outgoingMember = members[outgoing]
        incomingMember.status = .active
        outgoingMember.status = .camp
        members[outgoing] = incomingMember
        members[incoming] = outgoingMember
        run.roster = members
        run.syncActivePartyProjection()
        persistRun()
        refreshReadiness()
        return true
    }

    @discardableResult
    func setRosterStatus(_ status: RosterStatus, for member: PartyMember, confirmed: Bool = false) -> Bool {
        if status == .active, !member.rosterStatus.canBeActive {
            errorMessage = "Confirm that \(member.name) is available again before adding them to the active party."
            return false
        }
        if [.dead, .departed].contains(status), member.rosterStatus != status, !confirmed {
            let impact = member.rosterStatus == .active
                ? "They will stop contributing to readiness and route-level guidance."
                : "They will remain outside active readiness."
            let plan = member.buildId == nil
                ? "Their level and notes will be preserved."
                : "Their saved build, level, and equipment plan will be preserved."
            pendingRosterStatusChange = PendingRosterStatusChange(
                memberID: member.id,
                memberName: member.name,
                target: status,
                message: "\(impact) \(plan) Story outcomes and rewards remain separate confirmations."
            )
            return false
        }
        let undo = PartyUndoState(runID: run.id, message: "Moved \(member.name) to \(status.rawValue)", plan: run.partyPlan)
        guard run.applyRosterStatus(status, memberID: member.id) else {
            errorMessage = status == .active
                ? "Active party is full. Send someone to camp first."
                : "Could not update \(member.name)'s roster status."
            return false
        }
        partyUndoState = undo
        persistRun()
        refreshReadiness()
        return true
    }

    func confirmRosterStatusChange() {
        guard let pending = pendingRosterStatusChange,
              let member = roster.first(where: { $0.id == pending.memberID }) else {
            pendingRosterStatusChange = nil
            return
        }
        pendingRosterStatusChange = nil
        _ = setRosterStatus(pending.target, for: member, confirmed: true)
    }

    func cancelRosterStatusChange() {
        pendingRosterStatusChange = nil
    }

    func gearIsEquipped(_ gear: BuildGear, by member: PartyMember) -> Bool {
        run.equippedByMember?[member.id]?.contains(gear.itemKey) == true
    }

    /// The member's current plan for this act: build picks filtered by act and
    /// level, with any player slot swaps substituted in.
    func wantedGear(for member: PartyMember) -> [BuildGear] {
        wantedGear(for: member, in: selectedAct)
    }

    func wantedGear(for member: PartyMember, in act: Int) -> [BuildGear] {
        guard let buildId = member.buildId,
              let build = builds.first(where: { $0.id == buildId }) else { return [] }
        var gear = build.gear.filter { $0.act == act && $0.isAvailable(at: member.level) }
        let replacements = (run.plannedSlotOverrides?[member.id] ?? [:]).compactMap { storedKey, itemKey -> (String, ItemSummary)? in
            guard let item = itemCatalog.first(where: { $0.itemKey == itemKey }), item.act <= act else { return nil }
            let slot = LoadoutSlot.classify(item.slot, item: item.name)
            let effectiveKey = slot == .rings && storedKey.hasPrefix("\(slot.id)#")
                ? storedKey
                : (slot == .rings ? "\(slot.id)#0" : slot.id)
            return (effectiveKey, item)
        }
        for (key, item) in replacements.sorted(by: { $0.0 < $1.0 }) {
            let replacement = syntheticGear(from: item)
            let slot = LoadoutSlot.classify(item.slot, item: item.name)
            if slot == .rings {
                let field = Int(key.split(separator: "#").last ?? "0") ?? 0
                let ringIndices = gear.indices.filter {
                    LoadoutSlot.classify(gear[$0].slot, item: gear[$0].item) == .rings
                }
                if field < ringIndices.count {
                    gear[ringIndices[field]] = replacement
                } else {
                    gear.append(replacement)
                }
            } else {
                gear.removeAll { LoadoutSlot.classify($0.slot, item: $0.item) == slot }
                gear.append(replacement)
            }
        }
        return gear
    }

    /// A catalog item dressed as BuildGear so every existing gear surface
    /// (doll grid, drawer, detail view, maps) renders player swaps unchanged.
    func syntheticGear(from item: ItemSummary) -> BuildGear {
        BuildGear(
            item: item.name, slot: item.slot, priority: "Chosen", act: item.act,
            region: item.region, acquisition: item.acquisition,
            why: "Player-chosen replacement pick", source: item.wiki,
            minimumLevel: nil, maximumLevel: nil, requirement: nil,
            mapObjective: item.mapObjective, alternative: nil,
            effect: item.effect, acquire: item.acquire, wiki: item.wiki,
            icon: item.icon, gameX: item.gameX, gameY: item.gameY
        )
    }

    private var assignmentClaims: [GearLogic.GearClaim] {
        activeParty.compactMap { member in
            guard let buildId = member.buildId,
                  let build = builds.first(where: { $0.id == buildId }) else { return nil }
            return GearLogic.GearClaim(
                memberId: member.id, memberName: member.name, buildName: build.name,
                buildAssignedAt: run.buildAssignedAt?[member.id],
                itemKeys: Set(wantedGear(for: member).map(\.itemKey))
            )
        }
    }

    /// Deterministic item → member plan for the current act. Manual override
    /// wins; otherwise the build assigned earliest ("first to request"),
    /// ties broken alphabetically.
    var plannedAssignments: [String: String] {
        GearLogic.assignments(claims: assignmentClaims, overrides: run.gearAssignmentOverrides ?? [:])
    }

    func plannedOwner(ofItemKey key: String) -> PartyMember? {
        guard let memberId = plannedAssignments[key] else { return nil }
        return activeParty.first { $0.id == memberId }
    }

    func setGearAssignmentOverride(_ gear: BuildGear, to member: PartyMember) {
        partyUndoState = nil
        run.gearAssignmentOverrides = run.gearAssignmentOverrides ?? [:]
        run.gearAssignmentOverrides?[gear.itemKey] = member.id
        persistRun()
    }

    func slotOverride(for member: PartyMember, slot: LoadoutSlot) -> String? {
        slotOverride(for: member, cell: DollCell(slot: slot))
    }

    func slotOverride(for member: PartyMember, cell: DollCell) -> String? {
        resolvedSlotOverride(for: member, cell: cell)?.itemKey
    }

    func setSlotOverride(_ slot: LoadoutSlot, itemKey: String?, for member: PartyMember) {
        setSlotOverride(DollCell(slot: slot), itemKey: itemKey, for: member)
    }

    func setSlotOverride(_ cell: DollCell, itemKey: String?, for member: PartyMember) {
        partyUndoState = nil
        var all = run.plannedSlotOverrides ?? [:]
        var mine = all[member.id] ?? [:]
        if let existing = resolvedSlotOverride(for: member, cell: cell) {
            mine.removeValue(forKey: existing.key)
        }
        if cell.field == 0 { mine.removeValue(forKey: cell.slot.id) }
        mine[cell.id] = itemKey
        all[member.id] = mine.isEmpty ? nil : mine
        run.plannedSlotOverrides = all
        persistRun()
    }

    private func resolvedSlotOverride(for member: PartyMember, cell: DollCell) -> (key: String, itemKey: String)? {
        for (key, itemKey) in run.plannedSlotOverrides?[member.id] ?? [:] {
            guard let item = itemCatalog.first(where: { $0.itemKey == itemKey }) else { continue }
            let slot = LoadoutSlot.classify(item.slot, item: item.name)
            let effectiveID: String
            if slot == .rings {
                effectiveID = key.hasPrefix("\(slot.id)#") ? key : "\(slot.id)#0"
            } else {
                effectiveID = DollCell(slot: slot).id
            }
            if effectiveID == cell.id { return (key, itemKey) }
        }
        return nil
    }

    /// Cross-build claim on the same item: either the player already confirmed
    /// an owner, or several active plans want it and assignment recency
    /// ("first to request") decides who gets it.
    func gearConflict(for gear: BuildGear, member: PartyMember) -> GearConflict? {
        if let owner = gearOwner(gear), owner.id != member.id {
            return GearConflict(
                mine: false,
                short: "Equipped by \(owner.name)",
                detail: gearConflictDetail(gear, base: "\(owner.name) is the player-confirmed owner.")
            )
        }
        let key = gear.itemKey
        let rivals = activeParty.filter { other in
            other.id != member.id && wantedGear(for: other).contains { $0.itemKey == key }
        }
        guard !rivals.isEmpty, let planned = plannedOwner(ofItemKey: key) else { return nil }
        let rivalNames = rivals.map(\.name).joined(separator: ", ")
        if planned.id == member.id {
            return GearConflict(
                mine: true,
                short: "Also wanted by \(rivalNames)",
                detail: gearConflictDetail(gear, base: "\(member.name)'s build requested it first, so \(member.name) gets it. Open the item to hand it to someone else.")
            )
        }
        return GearConflict(
            mine: false,
            short: "Assigned to \(planned.name)",
            detail: gearConflictDetail(gear, base: "\(planned.name)'s build requested it first. Use “Give to \(member.name)” to override.")
        )
    }

    private func gearConflictDetail(_ gear: BuildGear, base: String) -> String {
        guard let alternative = gear.alternative, !alternative.isEmpty else {
            return "\(base) No equivalent item is listed; decide ownership before spending gold."
        }
        return "\(base) Alternative: \(alternative)"
    }

    func gearOwner(_ gear: BuildGear) -> PartyMember? {
        guard let ownerID = run.equipmentOwnerID(for: gear.itemKey) else { return nil }
        return roster.first(where: { $0.id == ownerID })
    }

    func toggleGear(_ gear: BuildGear, for member: PartyMember) {
        partyUndoState = nil
        let wasTargeted = gearIsTargeted(gear, for: member)
        guard gear.isMapObjective, run.toggleEquipment(itemKey: gear.itemKey, for: member.id) else { return }
        // Equipping the targeted item completes the target.
        if wasTargeted, gearIsEquipped(gear, by: member) {
            run.gearTarget = nil
        }
        persistRun()
    }

    func setStoryOutcome(_ outcome: String, confirmed: Bool) {
        run.setStoryOutcome(outcome, confirmed: confirmed)
        persistRun()
    }

    func setIncludeCampPlans(_ enabled: Bool) {
        run.includeCampPlans = enabled
        persistRun()
    }

    func setAllPartyLevels(_ level: Int) {
        guard var members = run.roster else { return }
        partyUndoState = nil
        members = members.map { member in
            var copy = member
            guard copy.rosterStatus == .active else { return copy }
            copy.level = level
            if let buildId = copy.buildId,
               let build = builds.first(where: { $0.id == buildId }),
               let plan = build.levels.last(where: { $0.level <= level }) {
                copy.className = plan.take
            }
            return copy
        }
        run.roster = members
        run.syncActivePartyProjection()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        refreshReadiness()
    }
}
