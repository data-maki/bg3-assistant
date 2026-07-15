import Foundation

/// Party, roster, and loadout editing: everything that mutates who is in the
/// run and what they carry. Route/overlay orchestration stays in AppState.
@MainActor
extension AppState {
    func togglePreparation(_ item: String) {
        guard let checkpoint = currentCheckpoint else { return }
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        if progress.checkedPreparation.contains(item) { progress.checkedPreparation.remove(item) }
        else { progress.checkedPreparation.insert(item) }
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        persistRun()
        Task { await refreshReadiness() }
    }

    func toggleCompletion(_ item: String) {
        guard let checkpoint = currentCheckpoint else { return }
        var progress = run.progress[checkpoint.id] ?? CheckpointProgress()
        if progress.checkedCompletion.contains(item) { progress.checkedCompletion.remove(item) }
        else { progress.checkedCompletion.insert(item) }
        progress.updatedAt = .now
        run.progress[checkpoint.id] = progress
        persistRun()
    }

    func updatePartyMember(_ member: PartyMember) {
        guard let index = run.roster?.firstIndex(where: { $0.id == member.id }) else { return }
        run.roster?[index] = member
        run.syncActivePartyProjection()
        if run.focusedWalkthroughStepId == nil {
            run.selectedCheckpointId = nil
            syncRegionToRecommendation()
        }
        persistRun()
        Task { await refreshReadiness() }
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
        guard run.applyRosterStatus(status, memberID: member.id) else {
            errorMessage = status == .active
                ? "Active party is full. Send someone to camp first."
                : "Could not update \(member.name)'s roster status."
            return false
        }
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

    func gearOwner(_ gear: BuildGear) -> PartyMember? {
        guard let ownerID = run.equipmentOwnerID(for: gear.itemKey) else { return nil }
        return roster.first(where: { $0.id == ownerID })
    }

    func toggleGear(_ gear: BuildGear, for member: PartyMember) {
        guard gear.isMapObjective, run.toggleEquipment(itemKey: gear.itemKey, for: member.id) else { return }
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
