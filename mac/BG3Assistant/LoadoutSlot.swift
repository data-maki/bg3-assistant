import Foundation

/// Canonical equipment slots, in BG3 inventory order. TSV slot strings map in.
enum LoadoutSlot: String, CaseIterable, Identifiable {
    case helmet = "Helmet"
    case armour = "Armour"
    case gloves = "Gloves"
    case boots = "Boots"
    case amulet = "Amulet"
    case rings = "Rings"
    case mainHand = "Main hand"
    case offHand = "Off-hand"
    case torch = "Torch"
    case ranged = "Ranged"
    case extras = "Camp & consumables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .helmet: "crown.fill"
        case .armour: "tshirt.fill"
        case .gloves: "hand.raised.fill"
        case .boots: "shoeprints.fill"
        case .amulet: "medal.fill"
        case .rings: "circlebadge.2.fill"
        case .mainHand: "hammer.fill"
        case .offHand: "shield.fill"
        case .torch: "flame.fill"
        case .ranged: "scope"
        case .extras: "backpack.fill"
        }
    }

    /// Torches arrive from the TSVs as slot "Melee", so the item name is the
    /// only signal that a pick belongs in the torch cell.
    static func classify(_ tsvSlot: String, item: String) -> LoadoutSlot {
        if item.lowercased().contains("torch") { return .torch }
        let slot = tsvSlot.lowercased()
        if slot.contains("head") { return .helmet }
        if slot.contains("chest") { return .armour }
        if slot.contains("off-hand") || slot.contains("shield") { return .offHand }
        if slot.contains("hands") { return .gloves }
        if slot.contains("feet") { return .boots }
        if slot.contains("amulet") { return .amulet }
        if slot.contains("ring") { return .rings }
        if slot.contains("ranged") { return .ranged }
        if slot.contains("melee") { return .mainHand }
        return .extras
    }
}

/// One visual cell in the doll grid: a canonical slot plus a field index for
/// slots that render more than one cell (two rings, as in the game).
struct DollCell: Hashable, Identifiable {
    let slot: LoadoutSlot
    var field: Int = 0

    var id: String { "\(slot.id)#\(field)" }
    var label: String { slot == .rings ? "Ring \(field + 1)" : slot.rawValue }

    /// The picks rendered in this cell: ring field 1 takes the top-priority
    /// ring, field 2 the rest; every other slot shows all of its items.
    func items(in grouped: [LoadoutSlot: [BuildGear]]) -> [BuildGear] {
        let slotItems = grouped[slot] ?? []
        guard slot == .rings else { return slotItems }
        return field == 0 ? Array(slotItems.prefix(1)) : Array(slotItems.dropFirst())
    }
}
