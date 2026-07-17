import SwiftUI

/// The planner's Loadout tab as a paper doll: a visible party strip, uniform
/// slot cells in BG3 inventory order, and a bottom drawer that previews an
/// item on hover and pins it on click for actions (target / equip / map).
struct LoadoutTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMemberId: String?
    @State private var pinnedSlot: LoadoutSlot?
    @State private var hoveredSlot: LoadoutSlot?
    @State private var showsLater = false

    private var party: [PartyMember] { appState.activeParty }

    private var member: PartyMember? {
        party.first(where: { $0.id == selectedMemberId }) ?? party.first
    }

    private var build: BuildSummary? {
        guard let id = member?.buildId else { return nil }
        return appState.builds.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 7) {
            header
            partyStrip
            memberSummary
            if let member, let build {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        dollGrid(build: build, member: member)
                        laterSection(build: build, member: member)
                        mapFooter(build: build, member: member)
                    }
                    .padding(.trailing, 6)
                }
                drawer(build: build, member: member)
            } else {
                emptyState
            }
        }
        .onChange(of: member?.id) { _, _ in
            pinnedSlot = nil
            hoveredSlot = nil
        }
    }

    // MARK: - Header / party

    private var availableGear: [BuildGear] {
        guard let member else { return [] }
        return appState.wantedGear(for: member)
            .sorted { GearLogic.priorityRank($0.priority) < GearLogic.priorityRank($1.priority) }
    }

    private var header: some View {
        let confirmable = availableGear.filter(\.isMapObjective)
        let confirmed = member.map { m in confirmable.filter { appState.gearIsEquipped($0, by: m) } } ?? []
        return HStack {
            Text("Loadout · Act \(appState.selectedAct)")
                .font(BG3Type.overline)
                .textCase(.uppercase)
                .foregroundStyle(BG3Theme.gold)
            Spacer()
            if !confirmable.isEmpty {
                Text("\(confirmed.count)/\(confirmable.count) confirmed")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(confirmed.count == confirmable.count ? BG3Theme.success : BG3Theme.mutedParchment)
            }
        }
    }

    private var partyStrip: some View {
        HStack(spacing: 5) {
            ForEach(party) { candidate in
                let selected = candidate.id == member?.id
                Button {
                    selectedMemberId = candidate.id
                } label: {
                    HStack(spacing: 4) {
                        if candidate.buildId == nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(BG3Theme.warning)
                        }
                        Text(candidate.name)
                            .font(BG3Type.captionBold)
                            .foregroundStyle(selected ? BG3Theme.parchment : BG3Theme.mutedParchment)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? BG3Theme.bronze.opacity(0.26) : BG3Theme.ink.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? BG3Theme.gold.opacity(0.6) : BG3Theme.bronze.opacity(0.3), lineWidth: 0.7))
                .help(candidate.buildId == nil ? "\(candidate.name) has no build assigned" : candidate.name)
                .accessibilityLabel(candidate.name)
                .accessibilityValue(selected ? "Selected" : candidate.buildId == nil ? "No build" : "")
            }
        }
    }

    @ViewBuilder private var memberSummary: some View {
        if let member {
            HStack(spacing: 6) {
                Text(build.map { "L\(member.level) · \($0.name)" } ?? "L\(member.level) · no build assigned")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .lineLimit(1)
                Spacer()
                Button {
                    appState.plannerTab = .party
                } label: {
                    Text("edit ›").font(BG3Type.captionBold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BG3Theme.gold)
                .help("Change level or build in the Party tab")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.rectangle.badge.plus")
                .font(.system(size: 26)).foregroundStyle(BG3Theme.mutedParchment)
            Text("\(member?.name ?? "This character") has no build yet.")
                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            Button("Choose a build in Party") { appState.plannerTab = .party }
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Doll grid

    private func dollGrid(build: BuildSummary, member: PartyMember) -> some View {
        let grouped = Dictionary(grouping: availableGear, by: { LoadoutSlot.classify($0.slot) })
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(LoadoutSlot.paired) { slot in
                    slotCell(slot, items: grouped[slot] ?? [], member: member)
                }
            }
            ForEach(LoadoutSlot.fullWidth) { slot in
                if let items = grouped[slot], !items.isEmpty {
                    slotCell(slot, items: items, member: member)
                }
            }
        }
    }

    private func slotCell(_ slot: LoadoutSlot, items: [BuildGear], member: PartyMember) -> some View {
        let pinned = pinnedSlot == slot
        let first = items.first
        return Button {
            pinnedSlot = pinned ? nil : slot
        } label: {
            HStack(spacing: 6) {
                Image(systemName: slot.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(first == nil ? BG3Theme.bronze.opacity(0.7) : BG3Theme.gold)
                    .frame(width: 15)
                VStack(alignment: .leading, spacing: 0) {
                    Text(first.map { items.count > 1 ? "\($0.item) +\(items.count - 1)" : $0.item } ?? "no pick")
                        .font(BG3Type.captionBold)
                        .foregroundStyle(first == nil ? BG3Theme.mutedParchment.opacity(0.7) : BG3Theme.parchment)
                        .lineLimit(1)
                    Text(slot.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(BG3Theme.mutedParchment.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                slotGlyph(items, member: member)
            }
            .padding(.horizontal, 7)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty)
        .background(RoundedRectangle(cornerRadius: 8).fill(pinned ? BG3Theme.bronze.opacity(0.26) : BG3Theme.ink.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(pinned ? BG3Theme.gold.opacity(0.7) : BG3Theme.bronze.opacity(items.isEmpty ? 0.18 : 0.35), lineWidth: pinned ? 1 : 0.7))
        .onHover { inside in
            if inside { hoveredSlot = slot } else if hoveredSlot == slot { hoveredSlot = nil }
        }
        .accessibilityLabel("\(slot.rawValue): \(first?.item ?? "no pick")")
    }

    @ViewBuilder private func slotGlyph(_ items: [BuildGear], member: PartyMember) -> some View {
        if let targeted = items.first(where: { appState.gearIsTargeted($0, for: member) }) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BG3Theme.gold)
                .help("Current target: \(targeted.item)")
        } else if let first = items.first {
            let confirmable = items.filter(\.isMapObjective)
            let equipped = confirmable.filter { appState.gearIsEquipped($0, by: member) }
            if !confirmable.isEmpty, equipped.count == confirmable.count {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.success)
            } else if let owner = appState.gearOwner(first), owner.id != member.id {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.warning)
                    .help("Equipped by \(owner.name)")
            } else if let planned = appState.plannedOwner(ofItemKey: first.itemKey), planned.id != member.id {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.warning)
                    .help("Assigned to \(planned.name) — their build requested it first")
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
        }
    }

    // MARK: - Drawer

    private func drawer(build: BuildSummary, member: PartyMember) -> some View {
        let grouped = Dictionary(grouping: availableGear, by: { LoadoutSlot.classify($0.slot) })
        let slot = pinnedSlot ?? hoveredSlot
        let items = slot.flatMap { grouped[$0] } ?? []
        return Group {
            if let slot, !items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(items) { gear in
                            GearDetailView(gear: gear, member: member, showsActions: pinnedSlot != nil)
                        }
                        if pinnedSlot == slot {
                            changePickSection(slot, items: items, member: member)
                        }
                        if pinnedSlot == nil {
                            Text("Click the slot to pin it and act on the item.")
                                .font(BG3Type.caption)
                                .foregroundStyle(BG3Theme.mutedParchment.opacity(0.8))
                        }
                    }
                    .padding(9)
                }
                .frame(maxHeight: 172)
                .frame(maxWidth: .infinity, alignment: .leading)
                .bg3InsetSurface(accent: pinnedSlot == slot ? BG3Theme.gold : BG3Theme.bronze)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(slot.rawValue) details")
            } else {
                idleDrawerSummary(member: member)
            }
        }
    }

    /// Alternatives for a pinned slot from the item catalog: any valid item
    /// for this slot obtainable by the current act, with its effect explained
    /// inline and on hover so trade-offs are visible before swapping.
    @ViewBuilder private func changePickSection(_ slot: LoadoutSlot, items: [BuildGear], member: PartyMember) -> some View {
        let options = appState.itemCatalog
            .filter { option in
                LoadoutSlot.classify(option.slot) == slot
                    && option.act <= appState.selectedAct
                    && !items.contains { $0.itemKey == option.itemKey }
            }
            .sorted { $0.name < $1.name }
        let overridden = appState.slotOverride(for: member, slot: slot) != nil
        if overridden || !options.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Change pick")
                        .font(BG3Type.overline).textCase(.uppercase)
                        .foregroundStyle(BG3Theme.gold)
                    Spacer()
                    if overridden {
                        Button("Revert to build pick") {
                            appState.setSlotOverride(slot, itemKey: nil, for: member)
                        }
                        .buttonStyle(.plain).font(BG3Type.captionBold)
                        .foregroundStyle(BG3Theme.warning)
                        .help("Drop the swapped-in item and restore the build's own pick")
                    }
                }
                ForEach(options) { option in
                    HStack(alignment: .top, spacing: 6) {
                        GearItemIcon(gear: appState.syntheticGear(from: option), size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.name)
                                .font(BG3Type.captionBold).foregroundStyle(BG3Theme.parchment)
                            Text(option.effect.isEmpty ? "No effect description yet — see the wiki." : option.effect)
                                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Button("Use") {
                            appState.setSlotOverride(slot, itemKey: option.itemKey, for: member)
                        }
                        .assistantActionButton(accent: BG3Theme.gold)
                    }
                    .help(option.effect.isEmpty ? option.name : option.effect)
                }
            }
            .padding(.top, 4)
        }
    }

    private func idleDrawerSummary(member: PartyMember) -> some View {
        let confirmable = availableGear.filter(\.isMapObjective)
        let confirmed = confirmable.filter { appState.gearIsEquipped($0, by: member) }
        let contested = availableGear.filter { appState.gearConflict(for: $0, member: member) != nil }
        var line = confirmable.isEmpty
            ? "No obtainable picks for this act yet."
            : "\(confirmed.count) of \(confirmable.count) picks confirmed"
        if !contested.isEmpty { line += " · \(contested.count) contested" }
        return HStack(spacing: 6) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 11))
                .foregroundStyle(BG3Theme.mutedParchment)
            Text("\(line) — hover a slot for details.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: BG3Theme.bronze.opacity(0.6))
    }

    // MARK: - Later + footer

    @ViewBuilder private func laterSection(build: BuildSummary, member: PartyMember) -> some View {
        let later = build.gear
            .filter { $0.act > appState.selectedAct || !$0.isAvailable(at: member.level) }
            .sorted {
                ($0.act, $0.minimumLevel ?? 1, GearLogic.priorityRank($0.priority))
                    < ($1.act, $1.minimumLevel ?? 1, GearLogic.priorityRank($1.priority))
            }
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    showsLater.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(BG3Theme.bronzeBright)
                        Text(later.count == 1 ? "Later · 1 item" : "Later · \(later.count) items")
                            .font(BG3Type.captionBold)
                            .foregroundStyle(BG3Theme.parchment)
                        Spacer()
                        Image(systemName: showsLater ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(BG3Theme.mutedParchment)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showsLater {
                    ForEach(later) { gear in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(BG3Theme.bronzeBright)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(gear.item).font(BG3Type.captionBold).foregroundStyle(BG3Theme.parchment)
                                Text(laterReason(gear, member: member))
                                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(8)
            .bg3InsetSurface(accent: BG3Theme.bronze.opacity(0.5))
        }
    }

    private func laterReason(_ gear: BuildGear, member: PartyMember) -> String {
        if gear.act > appState.selectedAct { return "Act \(gear.act) · \(gear.region)" }
        if let minimum = gear.minimumLevel, minimum > member.level {
            let requirement = gear.requirement?.isEmpty == false ? " · \(gear.requirement!)" : ""
            return "Unlocks at L\(minimum)\(requirement)"
        }
        return gear.requirement?.isEmpty == false ? gear.requirement! : gear.region
    }

    private func mapFooter(build: BuildSummary, member: PartyMember) -> some View {
        Button {
            appState.openCurrentActMap(buildId: build.id, item: nil, level: member.level)
        } label: {
            Label("Show all Act \(appState.selectedAct) pickups on the map", systemImage: "map.fill")
                .font(BG3Type.captionBold)
                .frame(maxWidth: .infinity)
        }
        .assistantActionButton()
    }
}

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
    case ranged = "Ranged"
    case extras = "Camp & consumables"

    var id: String { rawValue }

    /// Slots shown as a two-column grid, in reading order.
    static let paired: [LoadoutSlot] = [.helmet, .armour, .gloves, .boots, .amulet, .rings, .mainHand, .offHand]
    /// Slots rendered full-width below the grid (hidden when empty).
    static let fullWidth: [LoadoutSlot] = [.ranged, .extras]

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
        case .ranged: "scope"
        case .extras: "backpack.fill"
        }
    }

    static func classify(_ tsvSlot: String) -> LoadoutSlot {
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
