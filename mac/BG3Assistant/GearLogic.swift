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
    struct Pickup: Equatable, Identifiable {
        let gear: BuildGear
        let memberId: String
        let memberName: String

        /// Same key AppState uses to dedupe pickups: one row per member+item.
        var id: String { "\(memberId)|\(gear.itemKey)" }
    }

    /// Thematic identity of a route region. Ordering and membership are one
    /// table (`regionStages`); tints live in GearPresentation.
    enum RegionCluster: Equatable {
        case wilderness, settlement, hostile, underdark, forge, mountainPass, rivington, other
    }

    struct RegionStage {
        let keywords: [String]
        let cluster: RegionCluster
    }

    /// One canonical route-order table per act: earlier stage = earlier on the
    /// route. Both act-gear sorting and region tinting derive from this.
    static let regionStages: [Int: [RegionStage]] = [
        1: [
            RegionStage(keywords: ["nautiloid"], cluster: .other),
            RegionStage(keywords: ["anywhere"], cluster: .other),
            RegionStage(keywords: ["druid grove"], cluster: .wilderness),
            RegionStage(keywords: ["blighted village"], cluster: .settlement),
            RegionStage(keywords: ["apothecary"], cluster: .settlement),
            RegionStage(keywords: ["goblin camp", "shattered sanctum"], cluster: .hostile),
            RegionStage(keywords: ["waukeen"], cluster: .settlement),
            RegionStage(keywords: ["sunlit wetlands", "riverside teahouse"], cluster: .wilderness),
            RegionStage(keywords: ["risen road"], cluster: .wilderness),
            RegionStage(keywords: ["zhentarim"], cluster: .hostile),
            RegionStage(keywords: ["selûnite outpost"], cluster: .underdark),
            RegionStage(keywords: ["myconid colony"], cluster: .underdark),
            RegionStage(keywords: ["underdark"], cluster: .underdark),
            RegionStage(keywords: ["grymforge"], cluster: .forge),
            RegionStage(keywords: ["adamantine forge"], cluster: .forge),
            RegionStage(keywords: ["rosymorn monastery trail"], cluster: .mountainPass),
            RegionStage(keywords: ["rosymorn monastery"], cluster: .mountainPass),
            RegionStage(keywords: ["crèche y'llek"], cluster: .mountainPass),
        ],
        2: [
            RegionStage(keywords: ["ruined battlefield"], cluster: .underdark),
            RegionStage(keywords: ["last light inn"], cluster: .wilderness),
            RegionStage(keywords: ["reithwin"], cluster: .settlement),
            RegionStage(keywords: ["moonrise towers", "moonrise"], cluster: .hostile),
            RegionStage(keywords: ["gauntlet of shar"], cluster: .underdark),
            RegionStage(keywords: ["mind flayer colony", "mind flayer"], cluster: .hostile),
        ],
        3: [
            RegionStage(keywords: ["rivington", "circus of the last days", "circus"], cluster: .rivington),
            RegionStage(keywords: ["lower city"], cluster: .settlement),
            RegionStage(keywords: ["sorcerous sundries", "ramazith"], cluster: .settlement),
            RegionStage(keywords: ["cazador"], cluster: .hostile),
            RegionStage(keywords: ["murder tribunal"], cluster: .hostile),
            RegionStage(keywords: ["house of hope"], cluster: .hostile),
        ],
    ]

    /// Route position of a region within its act; unknown regions sort last.
    static func routeRank(region: String, act: Int) -> Int {
        let region = region.lowercased()
        let stages = regionStages[act] ?? []
        return stages.firstIndex { stage in
            stage.keywords.contains { region.contains($0) }
        } ?? stages.count
    }

    /// Cluster identity of a region, searched across acts in order so the
    /// result is deterministic when a region name matches more than one act.
    static func regionCluster(for region: String) -> RegionCluster {
        let region = region.lowercased()
        for act in regionStages.keys.sorted() {
            if let stage = regionStages[act]?.first(where: { $0.keywords.contains { region.contains($0) } }) {
                return stage.cluster
            }
        }
        return .other
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

    /// One active member's claim on gear: identity and the item keys their
    /// plan currently wants.
    struct GearClaim: Equatable {
        let memberId: String
        let memberName: String
        let itemKeys: Set<String>
    }

    /// Deterministic item → member assignment: a manual override wins when its
    /// target still claims the item; otherwise the alphabetically first
    /// claimant. One rule plus one legible default — recency tracking was
    /// deliberately removed.
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
