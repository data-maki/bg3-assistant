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
    private func partyUndoSnapshot(_ message: String) -> PartyUndoState {
        PartyUndoState(
            message: message,
            roster: run.roster ?? run.party,
            equippedByMember: run.equippedByMember ?? [:]
        )
    }

    private func recordPartyUndo(_ message: String) {
        partyUndoState = partyUndoSnapshot(message)
    }

    func undoLastPartyChange() {
        guard let undo = partyUndoState else { return }
        run.roster = undo.roster
        run.equippedByMember = undo.equippedByMember
        run.syncActivePartyProjection()
        partyUndoState = nil
        persistRun()
        Task { await refreshReadiness() }
    }

    @discardableResult
    func importBuild() async -> BuildSummary? {
        let url = loadoutURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            loadoutImportStatus = "Paste a public build URL first."
            return nil
        }
        guard hasOpenRouterKey else {
            loadoutImportNeedsKey = true
            loadoutImportStatus = "Add an OpenRouter API key in Settings to import this build."
            openSettings()
            return nil
        }
        guard !isImportingLoadout else { return nil }
        isImportingLoadout = true
        loadoutImportStatus = "Reading and processing the build…"
        defer { isImportingLoadout = false }
        do {
            let imported = try await backendClient.importBuild(LoadoutImportRequest(url: url))
            applyImportedBuild(imported)
            loadoutURLDraft = ""
            loadoutImportNeedsKey = false
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
        let hireling = WithersHireling.all.first { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }
        let companion = StoryCompanion.all.first { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }
        let defaultClass = hireling?.defaultClass ?? companion?.defaultClass ?? member.className
        reset.buildId = nil
        reset.className = member.isCustom == true ? nil : defaultClass
        reset.preparedTags = []
        reset.roleOverride = nil
        reset.abilityScores = member.isCustom == true ? .customDefault : .forClass(defaultClass)
        reset.abilityModifiers = []
        reset.usesBuildAbilityScores = false
        reset.sourceLoadoutId = nil
        run.roster?[index] = reset
        run.equippedByMember?[member.id] = nil
        run.buildAssignedAt?.removeValue(forKey: member.id)
        run.plannedSlotOverrides?.removeValue(forKey: member.id)
        run.syncActivePartyProjection()
        persistRun()
        Task { await refreshReadiness() }
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
        run.syncActivePartyProjection()
        persistRun()
        Task { await refreshReadiness() }
        return true
    }

    private func applyImportedBuild(_ imported: ImportedBuild) {
        builds.removeAll { $0.id == imported.build.id }
        builds.append(imported.build)
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

    func updatePartyMember(_ member: PartyMember) {
        guard let index = run.roster?.firstIndex(where: { $0.id == member.id }) else { return }
        run.roster?[index] = member
        run.syncActivePartyProjection()
        validateGearTarget()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        Task { await refreshReadiness() }
    }

    func updatePartyLevel(_ level: Int, for member: PartyMember) {
        var copy = member
        copy.level = level
        if let build = builds.first(where: { $0.id == copy.buildId }),
           let plan = build.levels.last(where: { $0.level <= level }) {
            copy.className = plan.take
        }
        updatePartyMember(copy)
    }

    func assignBuild(_ buildID: String?, to member: PartyMember) {
        recordPartyUndo("Changed \(member.name)'s build")
        var copy = member
        copy.buildId = buildID
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
            copy.usesBuildAbilityScores = false
            updatePartyMember(copy)
            return
        }
        if let plan = build.levels.last(where: { $0.level <= copy.level }) {
            copy.className = plan.take
        }
        let setup = AbilityProgression.activeSetup(in: build, at: copy.level)
        copy.abilityScores = setup?.finalScores ?? build.startingAbilityScores ?? copy.abilityScores
        // Permanent rewards belong to the character, not the selected build.
        copy.abilityModifiers = (copy.abilityModifiers ?? []).filter { $0.kind == .permanent }
        copy.usesBuildAbilityScores = true
        updatePartyMember(copy)
    }

    func applyAbilitySetup(_ setup: AbilitySetupPlan, to member: PartyMember) {
        recordPartyUndo("Recorded \(setup.label) for \(member.name)")
        var copy = member
        copy.abilityScores = setup.finalScores
        copy.usesBuildAbilityScores = true
        copy.appliedAbilitySetupId = setup.id
        updatePartyMember(copy)
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
        Task { await refreshReadiness() }
    }

    @discardableResult
    func swapIntoActive(_ member: PartyMember, replacing activeMember: PartyMember) -> Bool {
        guard member.rosterStatus == .camp, activeMember.rosterStatus == .active,
              var members = run.roster,
              let incoming = members.firstIndex(where: { $0.id == member.id }),
              let outgoing = members.firstIndex(where: { $0.id == activeMember.id }) else {
            errorMessage = "Only a Camp member can replace an active party member."
            return false
        }
        recordPartyUndo("Swapped \(member.name) for \(activeMember.name)")
        members[outgoing].status = .camp
        members[incoming].status = .active
        run.roster = members
        run.syncActivePartyProjection()
        persistRun()
        Task { await refreshReadiness() }
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
        let undo = partyUndoSnapshot("Moved \(member.name) to \(status.rawValue)")
        guard run.applyRosterStatus(status, memberID: member.id) else {
            errorMessage = status == .active
                ? "Active party is full. Send someone to camp first."
                : "Could not update \(member.name)'s roster status."
            return false
        }
        partyUndoState = undo
        persistRun()
        Task { await refreshReadiness() }
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

    /// Cross-build claim on the same item: either the player already confirmed
    /// an owner, or another active member's build wants it too and priority
    /// decides who wears it.
    func gearConflict(for gear: BuildGear, member: PartyMember) -> GearConflict? {
        if let owner = gearOwner(gear), owner.id != member.id {
            return GearConflict(
                mine: false,
                short: "Equipped by \(owner.name)",
                detail: gearConflictDetail(gear, base: "\(owner.name) is the player-confirmed owner.")
            )
        }
        let key = gear.itemKey
        let rivals: [(name: String, rank: Int)] = activeParty.compactMap { other in
            guard other.id != member.id,
                  let buildId = other.buildId,
                  let otherBuild = builds.first(where: { $0.id == buildId }),
                  let claim = otherBuild.gear.first(where: {
                      $0.act == selectedAct && $0.isAvailable(at: other.level) && $0.itemKey == key
                  })
            else { return nil }
            return (other.name, GearLogic.priorityRank(claim.priority))
        }
        guard let strongestRival = rivals.min(by: { $0.rank < $1.rank }) else { return nil }
        let myRank = GearLogic.priorityRank(gear.priority)
        if myRank < strongestRival.rank {
            return GearConflict(
                mine: true,
                short: "Also wanted by \(strongestRival.name)",
                detail: gearConflictDetail(gear, base: "\(strongestRival.name)'s build wants this too. \(member.name)'s build lists it at higher priority — \(member.name) wears it.")
            )
        }
        if myRank > strongestRival.rank {
            return GearConflict(
                mine: false,
                short: "Goes to \(strongestRival.name)",
                detail: gearConflictDetail(gear, base: "\(strongestRival.name)'s build lists this at higher priority.")
            )
        }
        return GearConflict(
            mine: true,
            short: "Contested with \(strongestRival.name)",
            detail: gearConflictDetail(gear, base: "Both \(member.name) and \(strongestRival.name) want this at the same priority.")
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
        Task { await refreshReadiness() }
    }
}
