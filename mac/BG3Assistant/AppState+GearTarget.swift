import Foundation

/// Player-chosen equipment goal. The target replaces the Now-page goal and
/// the peek headline until the item is acquired or the target is cleared;
/// route recommendation logic underneath is untouched.
extension AppState {
    /// Resolves the stored target against live party/build state. A stale
    /// target (member gone, build changed, act moved on) resolves to nil and
    /// the Now page falls back to the route goal.
    var gearTargetContext: (member: PartyMember, gear: BuildGear)? {
        guard let target = run.gearTarget,
              let member = activeParty.first(where: { $0.id == target.memberId }),
              member.buildId == target.buildId,
              let build = builds.first(where: { $0.id == target.buildId }),
              let gear = build.gear.first(where: { $0.id == target.gearId }),
              gear.act == selectedAct
        else { return nil }
        return (member, gear)
    }

    var gearTargetPath: [GearLogic.PathRow] {
        guard let context = gearTargetContext else { return [] }
        return GearLogic.pathRows(
            gear: context.gear,
            memberLevel: context.member.level,
            walkthrough: walkthrough,
            dispositions: run.walkthroughProgress ?? [:]
        )
    }

    func setGearTarget(_ gear: BuildGear, for member: PartyMember) {
        guard gear.act == selectedAct, let buildId = member.buildId else { return }
        run.gearTarget = GearTarget(memberId: member.id, buildId: buildId, gearId: gear.id)
        persistRun()
    }

    func clearGearTarget() {
        guard run.gearTarget != nil else { return }
        run.gearTarget = nil
        persistRun()
    }

    /// "Got it": equips the item for the target member (which also clears
    /// the target via the toggleGear hook) or, if it is somehow already
    /// equipped, just clears.
    func completeGearTarget() {
        guard let context = gearTargetContext else {
            clearGearTarget()
            return
        }
        if gearIsEquipped(context.gear, by: context.member) {
            clearGearTarget()
        } else {
            toggleGear(context.gear, for: context.member)
        }
    }

    func gearIsTargeted(_ gear: BuildGear, for member: PartyMember) -> Bool {
        guard let context = gearTargetContext else { return false }
        return context.member.id == member.id && context.gear.id == gear.id
    }

    /// Clears a target that no longer resolves (e.g. the member's build was
    /// reassigned). Called from party mutations.
    func validateGearTarget() {
        if run.gearTarget != nil, gearTargetContext == nil {
            run.gearTarget = nil
        }
    }

    /// Unowned, currently-obtainable planned gear across the active party —
    /// what the Route tab surfaces as pickups. A contested item surfaces only
    /// for its planned owner (assignment recency), and player slot swaps ride
    /// along like build picks.
    var routePickups: [GearLogic.Pickup] {
        var seen = Set<String>()
        var pickups: [GearLogic.Pickup] = []
        for member in activeParty {
            let wanted = wantedGear(for: member)
                .filter {
                    gearOwner($0) == nil
                        && (plannedOwner(ofItemKey: $0.itemKey)?.id ?? member.id) == member.id
                }
                .sorted { GearLogic.priorityRank($0.priority) < GearLogic.priorityRank($1.priority) }
            for gear in wanted {
                let key = "\(member.id)|\(gear.itemKey)"
                guard seen.insert(key).inserted else { continue }
                pickups.append(GearLogic.Pickup(gear: gear, memberId: member.id, memberName: member.name))
            }
        }
        return pickups
    }
}
