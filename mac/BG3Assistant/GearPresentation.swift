import SwiftUI

/// Presentation of gear identity: rarity and region-cluster tints.
/// Classification (which region belongs to which cluster) lives in GearLogic;
/// only the color mapping is presentation.
enum GearRarity: Equatable {
    case common
    case uncommon
    case rare
    case veryRare
    case legendary

    // Heuristic: the wiki effect text names the rarity. Structured rarity from
    // the data pipeline should replace this (ordering matters: "very rare"
    // must match before "rare").
    init(effect: String?) {
        let effect = effect?.lowercased() ?? ""
        if effect.contains("legendary") {
            self = .legendary
        } else if effect.contains("very rare") {
            self = .veryRare
        } else if effect.contains("rare") {
            self = .rare
        } else if effect.contains("uncommon") {
            self = .uncommon
        } else {
            self = .common
        }
    }

    var tint: Color {
        switch self {
        case .legendary: BG3Theme.rarityLegendary
        case .veryRare: BG3Theme.rarityVeryRare
        case .rare: BG3Theme.rarityRare
        case .uncommon: BG3Theme.rarityUncommon
        case .common: BG3Theme.parchment
        }
    }
}

extension GearLogic.RegionCluster {
    var tint: Color {
        switch self {
        case .wilderness: BG3Theme.clusterWilderness
        case .settlement: BG3Theme.clusterSettlement
        case .hostile: BG3Theme.clusterHostile
        case .underdark: BG3Theme.clusterUnderdark
        case .forge: BG3Theme.clusterForge
        case .mountainPass: BG3Theme.clusterMountainPass
        case .rivington: BG3Theme.clusterRivington
        case .other: BG3Theme.mutedParchment
        }
    }
}

extension BuildGear {
    var rarityTint: Color { GearRarity(effect: effect).tint }
    var regionTint: Color { GearLogic.regionCluster(for: region).tint }
}
