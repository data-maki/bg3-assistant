import Foundation

/// Pure derivation logic for gear targets and route pickups. No gear→step
/// data exists in the guide, so the path to an item is derived by matching
/// the gear's region string against walkthrough areas; where the strings
/// don't align the path degrades to the acquisition text alone — never
/// invented steps.
enum GearLogic {
    /// One row of a gear target's path, in display order.
    enum PathRow: Equatable {
        case levelGate(required: Int, partyLevel: Int)
        case step(WalkthroughStep, done: Bool)
        case info(String)
        case acquisition(String)
    }

    /// One unowned build item surfaced on the route, tagged with who wants it.
    struct Pickup: Equatable {
        let gear: BuildGear
        let memberId: String
        let memberName: String
    }

    static func regionParts(_ region: String) -> [String] {
        region.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Walkthrough steps that plausibly take the player to the gear's region,
    /// in route order. Case-insensitive containment in either direction so
    /// "Zhentarim Hideout" matches an area named "Hideout" and vice versa.
    static func matchingSteps(for gear: BuildGear, in walkthrough: [WalkthroughStep]) -> [WalkthroughStep] {
        let parts = regionParts(gear.region).map { $0.lowercased() }
        guard !parts.isEmpty else { return [] }
        return walkthrough
            .filter { step in
                let fields = [step.area.lowercased(), step.region.lowercased()].filter { !$0.isEmpty }
                return parts.contains { part in
                    fields.contains { $0.contains(part) || part.contains($0) }
                }
            }
            .sorted { $0.order < $1.order }
    }

    static func pathRows(
        gear: BuildGear,
        memberLevel: Int,
        walkthrough: [WalkthroughStep],
        dispositions: [String: CheckpointDisposition]
    ) -> [PathRow] {
        var rows: [PathRow] = []
        if let minimum = gear.minimumLevel, memberLevel < minimum {
            rows.append(.levelGate(required: minimum, partyLevel: memberLevel))
        }
        for step in matchingSteps(for: gear, in: walkthrough) {
            rows.append(.step(step, done: dispositions[step.id] == .completed))
        }
        if let requirement = gear.requirement, !requirement.isEmpty {
            rows.append(.info(requirement))
        }
        rows.append(.acquisition(acquireText(gear)))
        return rows
    }

    /// Wiki-sourced pickup text when present, else the guide's acquisition.
    static func acquireText(_ gear: BuildGear) -> String {
        if let acquire = gear.acquire, !acquire.isEmpty { return acquire }
        return gear.acquisition
    }

    /// Buckets pickups under the phase of the first route step that reaches
    /// their region; unmatched items go to `other` so nothing is dropped.
    static func pickupsByPhase(
        _ pickups: [Pickup],
        walkthrough: [WalkthroughStep]
    ) -> (byPhase: [Int: [Pickup]], other: [Pickup]) {
        var byPhase: [Int: [Pickup]] = [:]
        var other: [Pickup] = []
        for pickup in pickups {
            if let first = matchingSteps(for: pickup.gear, in: walkthrough).first {
                byPhase[first.phaseOrder, default: []].append(pickup)
            } else {
                other.append(pickup)
            }
        }
        return (byPhase, other)
    }

    /// One active member's claim on gear: identity, tie-break names, when
    /// their build was assigned, and the item keys their plan currently wants.
    struct GearClaim: Equatable {
        let memberId: String
        let memberName: String
        let buildName: String
        let buildAssignedAt: Date?
        let itemKeys: Set<String>
    }

    /// Deterministic item → member assignment. Manual override wins when its
    /// target still claims the item; otherwise the earliest build assignment
    /// ("first to request"), then alphabetical build name, member name, id.
    static func assignments(
        claims: [GearClaim],
        overrides: [String: String]
    ) -> [String: String] {
        var result: [String: String] = [:]
        let allKeys = claims.reduce(into: Set<String>()) { $0.formUnion($1.itemKeys) }
        for key in allKeys {
            let claimants = claims.filter { $0.itemKeys.contains(key) }
            if let chosen = overrides[key], claimants.contains(where: { $0.memberId == chosen }) {
                result[key] = chosen
                continue
            }
            result[key] = claimants.min { lhs, rhs in
                let lhsDate = lhs.buildAssignedAt ?? .distantFuture
                let rhsDate = rhs.buildAssignedAt ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                if lhs.buildName.lowercased() != rhs.buildName.lowercased() {
                    return lhs.buildName.lowercased() < rhs.buildName.lowercased()
                }
                if lhs.memberName.lowercased() != rhs.memberName.lowercased() {
                    return lhs.memberName.lowercased() < rhs.memberName.lowercased()
                }
                return lhs.memberId < rhs.memberId
            }?.memberId
        }
        return result
    }

    static func priorityRank(_ priority: String) -> Int {
        ["Required", "Core", "Upgrade", "Starter", "Support", "Defence", "Supply", "Intentional", "Optional", "Endgame"]
            .firstIndex(of: priority) ?? 99
    }
}
