import SwiftUI

/// The planner's Loadout tab as a paper doll: a visible party strip, uniform
/// slot cells in BG3 inventory order, and a bottom drawer that previews an
/// item on hover and pins it on click for actions (target / equip / map).
struct LoadoutTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMemberId: String?
    @State private var pinnedCell: DollCell?
    @State private var hoveredCell: DollCell?
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
            pinnedCell = nil
            hoveredCell = nil
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

    /// Grid rows in BG3 inventory order; `nil` leaves a cell blank so the two
    /// ring fields stack in the right column. Weapon and off-hand sit on the
    /// left, torch and bow on the right.
    private static let dollRows: [[DollCell?]] = [
        [DollCell(slot: .helmet), DollCell(slot: .armour)],
        [DollCell(slot: .gloves), DollCell(slot: .boots)],
        [DollCell(slot: .amulet), DollCell(slot: .rings, field: 0)],
        [nil, DollCell(slot: .rings, field: 1)],
        [DollCell(slot: .mainHand), DollCell(slot: .torch)],
        [DollCell(slot: .offHand), DollCell(slot: .ranged)],
    ]

    private var groupedGear: [LoadoutSlot: [BuildGear]] {
        Dictionary(grouping: availableGear) { LoadoutSlot.classify($0.slot, item: $0.item) }
    }

    private func dollGrid(build: BuildSummary, member: PartyMember) -> some View {
        let grouped = groupedGear
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.dollRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(Self.dollRows[rowIndex], id: \.self) { cell in
                        if let cell {
                            slotCell(cell, items: cell.items(in: grouped), member: member)
                        } else {
                            Color.clear
                                .frame(height: 42)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            if let extras = grouped[.extras], !extras.isEmpty {
                slotCell(DollCell(slot: .extras), items: extras, member: member)
            }
        }
    }

    private func slotCell(_ cell: DollCell, items: [BuildGear], member: PartyMember) -> some View {
        let pinned = pinnedCell == cell
        let first = items.first
        let accessibilityText = [cell.label, first?.item ?? "no pick", first?.region]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return Button {
            pinnedCell = pinned ? nil : cell
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cell.slot.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(first == nil ? BG3Theme.bronze.opacity(0.7) : BG3Theme.gold)
                    .frame(width: 15)
                if let first {
                    GearItemIcon(gear: first, size: 28, borderColor: first.rarityTint)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(first.map { items.count > 1 ? "\($0.item) +\(items.count - 1)" : $0.item } ?? "no pick")
                        .font(BG3Type.captionBold)
                        .foregroundStyle(first?.rarityTint ?? BG3Theme.mutedParchment.opacity(0.7))
                        .lineLimit(1)
                    if let first {
                        Text(first.region.isEmpty ? "Location unknown" : first.region)
                            .font(.system(size: 9))
                            .foregroundStyle(first.regionTint)
                            .lineLimit(1)
                    }
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
            if inside { hoveredCell = cell } else if hoveredCell == cell { hoveredCell = nil }
        }
        .accessibilityLabel(accessibilityText)
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
        let grouped = groupedGear
        let cell = pinnedCell ?? hoveredCell
        let cellItems = cell.map { $0.items(in: grouped) } ?? []
        return Group {
            if let cell, !cellItems.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(cellItems) { gear in
                            GearDetailView(gear: gear, member: member, showsActions: pinnedCell != nil)
                        }
                        if pinnedCell == cell {
                            changePickSection(cell, items: grouped[cell.slot] ?? [], member: member)
                        }
                        if pinnedCell == nil {
                            Text("Click the slot to pin it and act on the item.")
                                .font(BG3Type.caption)
                                .foregroundStyle(BG3Theme.mutedParchment.opacity(0.8))
                        }
                    }
                    .padding(9)
                }
                .frame(maxHeight: 172)
                .frame(maxWidth: .infinity, alignment: .leading)
                .bg3InsetSurface(accent: pinnedCell == cell ? BG3Theme.gold : BG3Theme.bronze)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(cell.label) details")
            } else {
                idleDrawerSummary(member: member)
            }
        }
    }

    /// Alternatives for a pinned slot from the item catalog: any valid item
    /// for this slot obtainable by the current act, with its effect explained
    /// inline and on hover so trade-offs are visible before swapping.
    @ViewBuilder private func changePickSection(_ cell: DollCell, items: [BuildGear], member: PartyMember) -> some View {
        let options = appState.itemCatalog
            .filter { option in
                LoadoutSlot.classify(option.slot, item: option.name) == cell.slot
                    && option.act <= appState.selectedAct
                    && !items.contains { $0.itemKey == option.itemKey }
            }
            .sorted { $0.name < $1.name }
        let overridden = appState.slotOverride(for: member, cell: cell) != nil
        if overridden || !options.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Change pick")
                        .font(BG3Type.overline).textCase(.uppercase)
                        .foregroundStyle(BG3Theme.gold)
                    Spacer()
                    if overridden {
                        Button("Revert to build pick") {
                            appState.setSlotOverride(cell, itemKey: nil, for: member)
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
                            appState.setSlotOverride(cell, itemKey: option.itemKey, for: member)
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
            BG3Disclosure(
                title: later.count == 1 ? "Later · 1 item" : "Later · \(later.count) items",
                systemImage: "lock.fill", tint: BG3Theme.bronzeBright,
                inset: true, isExpanded: $showsLater
            ) {
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
