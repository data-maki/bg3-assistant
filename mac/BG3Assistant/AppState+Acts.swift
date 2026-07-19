import AppKit
import Foundation

@MainActor
extension AppState {
    func actGuide(for act: Int) -> ActGuideSummary? {
        acts.first { $0.act == act }
    }

    var currentActGuide: ActGuideSummary? {
        actGuide(for: selectedAct)
    }

    func nextActGuide(after act: Int) -> ActGuideSummary? {
        actGuide(for: act + 1)
    }

    var nextActGuide: ActGuideSummary? {
        nextActGuide(after: selectedAct)
    }

    var actHeaderTitle: String {
        let context = activeRouteAvailable
            ? currentActivityTitle
            : currentActGuide?.title ?? "Guide data unavailable"
        return "Act \(selectedAct): \(context)"
    }

    func actGear(for act: Int) -> [BuildGear] {
        if let record = run.lockedActRecord(for: act) {
            if let gear = record.gear { return sortActGear(gear) }
            let current = Dictionary(uniqueKeysWithValues: plannedActGear(for: act).map { ($0.itemKey, $0) })
            let legacy = record.gearReview.keys.compactMap { key in
                current[key] ?? itemCatalog.first(where: { $0.itemKey == key }).map(syntheticGear)
            }
            return sortActGear(legacy)
        }
        return sortActGear(plannedActGear(for: act))
    }

    private func plannedActGear(for act: Int) -> [BuildGear] {
        var unique: [String: BuildGear] = [:]
        for member in activeParty {
            for gear in wantedGear(for: member, in: act) where gear.act == act && gear.isMapObjective {
                if unique[gear.itemKey] == nil { unique[gear.itemKey] = gear }
            }
        }
        return Array(unique.values)
    }

    private func sortActGear(_ gear: [BuildGear]) -> [BuildGear] {
        gear.sorted { lhs, rhs in
            let lhsRank = GearLogic.routeRank(region: lhs.region, act: lhs.act)
            let rhsRank = GearLogic.routeRank(region: rhs.region, act: rhs.act)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (lhs.region, lhs.item) < (rhs.region, rhs.item)
        }
    }

    var currentActGear: [BuildGear] {
        actGear(for: selectedAct)
    }

    func actGearReviewStatus(for gear: BuildGear, in act: Int) -> ActGearReviewStatus? {
        if let locked = run.lockedActGearReviewStatus(for: gear.itemKey, in: act) {
            return locked
        }
        if gearOwner(gear) != nil { return .obtained }
        return run.actGearReview[act]?[gear.itemKey]
    }

    func actGearReviewStatus(for gear: BuildGear) -> ActGearReviewStatus? {
        actGearReviewStatus(for: gear, in: selectedAct)
    }

    func setActGearReview(_ status: ActGearReviewStatus, for gear: BuildGear, in act: Int) {
        guard !run.actLedgerIsLocked(act) else { return }
        var reviews = run.actGearReview
        var actReview = reviews[act] ?? [:]
        actReview[gear.itemKey] = status
        reviews[act] = actReview
        run.actGearReview = reviews
        persistRun()
    }

    func setActGearReview(_ status: ActGearReviewStatus, for gear: BuildGear) {
        setActGearReview(status, for: gear, in: selectedAct)
    }

    func unresolvedActGear(for act: Int) -> [BuildGear] {
        actGear(for: act).filter { actGearReviewStatus(for: $0, in: act) == nil }
    }

    var unresolvedActGear: [BuildGear] {
        unresolvedActGear(for: selectedAct)
    }

    func reviewedActGear(for act: Int) -> [BuildGear] {
        actGear(for: act).filter { actGearReviewStatus(for: $0, in: act) != nil }
    }

    var reviewedActGear: [BuildGear] {
        reviewedActGear(for: selectedAct)
    }

    func actRouteConsequences(for act: Int) -> [String] {
        if act == selectedAct, loadedGuideAct == act, loadedRouteAvailable {
            return act == 1
                ? actTwoBlockers
                : RunSafety.routeConsequences(route: route, dispositions: checkpointDispositions)
        }
        guard let count = run.actTransitions.first(where: { $0.fromAct == act })?.unresolvedRouteCount,
              count > 0 else { return [] }
        return ["Advanced with \(count) unresolved route consequence\(count == 1 ? "" : "s")."]
    }

    func actRouteConsequenceCount(for act: Int) -> Int {
        if act == selectedAct, loadedGuideAct == act, loadedRouteAvailable {
            return actRouteConsequences(for: act).count
        }
        return run.lockedActRecord(for: act)?.unresolvedRouteCount ?? 0
    }

    var currentActRouteConsequences: [String] {
        actRouteConsequences(for: selectedAct)
    }

    var actTransitionBlockedReason: String? {
        guard selectedAct < 3 else { return "Act 3 is the final act." }
        guard nextActGuide != nil else { return "The next act database is not installed." }
        guard activeGuideLoaded else { return "Act \(selectedAct) guide data must finish loading before this gate can unlock." }
        if !activeRouteAvailable {
            return "Act \(selectedAct) route coverage must be reviewed before this gate can unlock."
        }
        if !unresolvedActGear.isEmpty {
            return "Review \(unresolvedActGear.count) equipment item\(unresolvedActGear.count == 1 ? "" : "s") first."
        }
        return nil
    }

    var finalActBlockedReason: String? {
        guard selectedAct == 3 else { return "Only Act 3 can complete the run." }
        guard run.finalActRecord == nil else { return "The final Act 3 ledger is already locked." }
        guard activeGuideLoaded, activeRouteAvailable else { return "Act 3 guide data must finish loading first." }
        guard activeWalkthroughSteps.isEmpty else {
            return "Resolve or deliberately skip \(activeWalkthroughSteps.count) route step\(activeWalkthroughSteps.count == 1 ? "" : "s") first."
        }
        guard unresolvedActGear.isEmpty else {
            return "Review \(unresolvedActGear.count) equipment item\(unresolvedActGear.count == 1 ? "" : "s") first."
        }
        return nil
    }

    func advanceToNextAct(acceptingRouteConsequences: Bool) {
        guard selectedAct < 3, nextActGuide != nil, actTransitionBlockedReason == nil else { return }
        let consequences = currentActRouteConsequences
        guard consequences.isEmpty || acceptingRouteConsequences else { return }

        var review: [String: ActGearReviewStatus] = [:]
        for gear in currentActGear {
            guard let status = actGearReviewStatus(for: gear) else { return }
            review[gear.itemKey] = status
        }
        let fromAct = selectedAct
        let toAct = fromAct + 1
        let destination = nextActGuide
        let gear = currentActGear
        var transitions = run.actTransitions
        transitions.removeAll { $0.fromAct == fromAct }
        transitions.append(ActTransitionRecord(
            fromAct: fromAct,
            toAct: toAct,
            gearReview: review,
            gear: gear,
            unresolvedRouteCount: consequences.count,
            advancedAt: .now
        ))
        run.actTransitions = transitions
        run.selectedAct = toAct
        run.selectedCheckpointId = nil
        run.focusedWalkthroughStepId = nil
        run.mapRegion = destination?.title ?? "Act \(toAct)"
        combatCardPinned = false
        moreContextExpanded = false
        plannerTab = .act
        persistRun()
        resetGuideContext()
    }

    func finalizeActThree(acceptingRouteConsequences: Bool) {
        guard selectedAct == 3, finalActBlockedReason == nil else { return }
        let consequences = currentActRouteConsequences
        guard consequences.isEmpty || acceptingRouteConsequences else { return }
        let gear = currentActGear
        var review: [String: ActGearReviewStatus] = [:]
        for item in gear {
            guard let status = actGearReviewStatus(for: item) else { return }
            review[item.itemKey] = status
        }
        run.finalActRecord = ActTransitionRecord(
            fromAct: 3,
            toAct: 3,
            gearReview: review,
            gear: gear,
            unresolvedRouteCount: consequences.count,
            advancedAt: .now
        )
        persistRun()
    }

    func openCurrentActMap(buildId: String? = nil, item: String? = nil, level: Int? = nil) {
        openActMap(selectedAct, buildId: buildId, item: item, level: level)
    }

    func openActMap(_ act: Int, buildId: String? = nil, item: String? = nil, level: Int? = nil) {
        guard let handoff = actGuide(for: act)?.mapHandoff else { return }
        switch handoff {
        case .external(let url):
            NSWorkspace.shared.open(url)
        case .local:
            openLocalMap(buildId: buildId, item: item, level: level)
        }
    }
}
