import Foundation

/// Canonical equipment slots, in BG3 inventory order. TSV slot strings map in.
enum LoadoutSlot: String, CaseIterable, Identifiable {
    case helmet = "Helmet"
    case cloak = "Cape"
    case armour = "Armour"
    case gloves = "Gloves"
    case boots = "Boots"
    case instrument = "Instrument"
    case amulet = "Amulet"
    case rings = "Rings"
    case mainHand = "Main hand"
    case offHand = "Off-hand"
    case ranged = "Ranged"
    case extras = "Camp & consumables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .helmet: "crown.fill"
        case .cloak: "wind"
        case .armour: "tshirt.fill"
        case .gloves: "hand.raised.fill"
        case .boots: "shoeprints.fill"
        case .instrument: "music.note"
        case .amulet: "medal.fill"
        case .rings: "circlebadge.2.fill"
        case .mainHand: "figure.fencing"
        case .offHand: "shield.fill"
        case .ranged: "scope"
        case .extras: "backpack.fill"
        }
    }

    var label: String {
        switch self {
        case .armour: "Armor"
        case .boots: "Shoes"
        case .amulet: "Necklace"
        case .rings: "Ring"
        case .mainHand: "Sword"
        case .offHand: "Shield / 2nd Sword"
        case .ranged: "Bow"
        default: rawValue
        }
    }

    static func classify(_ tsvSlot: String, item: String) -> LoadoutSlot {
        if item.lowercased().contains("torch") { return .extras }
        let slot = tsvSlot.lowercased()
        if slot.contains("head") { return .helmet }
        if slot.contains("cloak") || slot.contains("cape") { return .cloak }
        if slot.contains("chest") { return .armour }
        if slot.contains("off-hand") || slot.contains("shield") { return .offHand }
        if slot.contains("hands") { return .gloves }
        if slot.contains("feet") { return .boots }
        if slot.contains("instrument") { return .instrument }
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
    var label: String { slot == .rings ? "Ring \(field + 1)" : slot.label }
    var emptyLabel: String { "\(label): no pick" }

    static let paperDollRows: [[DollCell]] = [
        [DollCell(slot: .helmet), DollCell(slot: .amulet)],
        [DollCell(slot: .cloak), DollCell(slot: .rings, field: 0)],
        [DollCell(slot: .armour), DollCell(slot: .rings, field: 1)],
        [DollCell(slot: .gloves), DollCell(slot: .mainHand)],
        [DollCell(slot: .boots), DollCell(slot: .offHand)],
        [DollCell(slot: .instrument), DollCell(slot: .ranged)],
    ]

    /// The picks rendered in this cell: ring field 1 takes the top-priority
    /// ring, field 2 the rest; every other slot shows all of its items.
    func items(in grouped: [LoadoutSlot: [BuildGear]]) -> [BuildGear] {
        let slotItems = grouped[slot] ?? []
        guard slot == .rings else { return slotItems }
        return field == 0 ? Array(slotItems.prefix(1)) : Array(slotItems.dropFirst())
    }
}
