import SwiftUI

/// BG3-style character sheet for the planner: rotate through the party, see
/// the recommended item for every equipment slot in the selected act, where to
/// pick each piece up, and whether another party member's build wants the same
/// item (single-copy conflicts are exactly why team composition matters).
struct LoadoutTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var memberIndex = 0

    var body: some View {
        VStack(spacing: 8) {
            header
            characterRotator
            if let member, let build {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        slotGrid(build: build, member: member)
                        laterGear(build: build, member: member)
                        footer(build: build, member: member)
                    }
                    .padding(.trailing, 6)
                }
            } else {
                emptyState
            }
        }
        .onChange(of: appState.loadoutMembers.count) { _, count in
            memberIndex = min(memberIndex, max(0, count - 1))
        }
    }

    // MARK: - Party selection

    private var party: [PartyMember] { appState.loadoutMembers }

    private var member: PartyMember? {
        party.indices.contains(memberIndex) ? party[memberIndex] : party.first
    }

    private var build: BuildSummary? {
        guard let id = member?.buildId else { return nil }
        return appState.builds.first { $0.id == id }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHARACTER LOADOUT").font(.system(.caption, design: .serif).bold()).foregroundStyle(BG3Theme.gold)
                Text("Wear these, in this order").font(.system(.headline, design: .serif))
                Text(appState.run.equipmentOwnershipKnown == true ? "Checkmarks are player-confirmed" : "Tap a circle when an item is equipped")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Act", selection: Binding(
                get: { appState.selectedAct },
                set: { act in appState.setSelectedAct(act) }
            )) {
                ForEach(1...3, id: \.self) { act in Text("Act \(act)").tag(act) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 164)
            .controlSize(.small)
            .accessibilityLabel("Loadout act")
        }
    }

    private var characterRotator: some View {
        HStack(spacing: 8) {
            rotateButton("chevron.left", label: "Previous character") {
                memberIndex = (memberIndex - 1 + max(party.count, 1)) % max(party.count, 1)
            }
            VStack(spacing: 1) {
                Text(member?.name ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(BG3Theme.parchment)
                Text(subtitleLine)
                    .font(.caption2).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityValue("Character \(memberIndex + 1) of \(party.count)")
            rotateButton("chevron.right", label: "Next character") {
                memberIndex = (memberIndex + 1) % max(party.count, 1)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 7)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var subtitleLine: String {
        guard let member else { return "" }
        if let build { return "L\(member.level) · \(build.name)" }
        return "L\(member.level) · no build assigned"
    }

    private func rotateButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).frame(width: 24, height: 30)
        }
        .assistantGlassButton().tint(BG3Theme.bronzeBright)
        .disabled(party.count < 2)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.rectangle.badge.plus")
                .font(.system(size: 26)).foregroundStyle(.secondary)
            Text("\(member?.name ?? "This character") has no build yet.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Pick a build in Party") { appState.plannerTab = .party }
                .assistantGlassButton().tint(BG3Theme.bronzeBright)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Slots

    private func availableGear(_ build: BuildSummary, member: PartyMember) -> [BuildGear] {
        build.gear
            .filter { $0.act <= appState.selectedAct && $0.isAvailable(at: member.level) }
            .sorted { priorityRank($0.priority) < priorityRank($1.priority) }
    }

    private func slotGrid(build: BuildSummary, member: PartyMember) -> some View {
        let grouped = Dictionary(grouping: availableGear(build, member: member), by: { LoadoutSlot.classify($0.slot) })
        let columns = [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]
        return VStack(alignment: .leading, spacing: 7) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                ForEach(LoadoutSlot.paired) { slot in
                    slotCell(slot, items: grouped[slot] ?? [], build: build, member: member)
                }
            }
            ForEach(LoadoutSlot.fullWidth) { slot in
                if let items = grouped[slot], !items.isEmpty {
                    slotCell(slot, items: items, build: build, member: member)
                }
            }
        }
    }

    private func slotCell(_ slot: LoadoutSlot, items: [BuildGear], build: BuildSummary, member: PartyMember) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: slot.icon).font(.system(size: 9.5)).foregroundStyle(BG3Theme.gold)
                Text(slot.rawValue.uppercased())
                    .font(.system(size: 8.5, weight: .heavy, design: .serif))
                    .foregroundStyle(BG3Theme.gold)
                Spacer(minLength: 0)
            }
            if items.isEmpty {
                Text("No reviewed pick").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(items) { gear in
                    gearEntry(gear, build: build, member: member)
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bg3InsetSurface(accent: items.isEmpty ? BG3Theme.bronze.opacity(0.35) : BG3Theme.bronze)
    }

    private func gearEntry(_ gear: BuildGear, build: BuildSummary, member: PartyMember) -> some View {
        let conflict = conflict(for: gear, member: member)
        return HStack(alignment: .top, spacing: 6) {
            itemIcon(gear)
            VStack(alignment: .leading, spacing: 1) {
                Text(gear.item)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.parchment).lineLimit(1)
                Text(pickupLine(gear))
                    .font(.caption2).foregroundStyle(BG3Theme.mutedParchment).lineLimit(2)
                if let requirement = gear.requirement, !requirement.isEmpty {
                    Text(requirement).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                }
                if let conflict {
                    Label(conflict.short, systemImage: conflict.mine ? "exclamationmark.triangle.fill" : "arrow.uturn.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(conflict.mine ? Color.orange : Color(red: 1.0, green: 0.55, blue: 0.45))
                        .help(conflict.detail)
                }
            }
            Spacer(minLength: 2)
            if gear.isMapObjective {
                let equipped = appState.gearIsEquipped(gear, by: member)
                let owner = appState.gearOwner(gear)
                Button {
                    appState.toggleGear(gear, for: member)
                } label: {
                    Image(systemName: equipped ? "checkmark.circle.fill" : owner == nil ? "circle" : "arrow.left.arrow.right.circle")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(equipped ? BG3Theme.success : owner == nil ? BG3Theme.mutedParchment : Color.orange)
                .help(equipped ? "Remove confirmed assignment" : owner.map { "Transfer from \($0.name)" } ?? "Confirm \(member.name) has this")
                .accessibilityLabel(equipped ? "Equipped by \(member.name)" : owner.map { "Transfer from \($0.name) to \(member.name)" } ?? "Mark equipped by \(member.name)")
            }
            if gear.act == 1 && gear.isMapObjective {
                Button {
                    appState.openActOneMap(buildId: build.id, item: gear.item, level: member.level)
                } label: {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(BG3Theme.bronzeBright)
                .help("Show the pickup on the map")
            }
        }
        .help(gear.effect?.isEmpty == false ? gear.effect! : gear.why)
    }

    @ViewBuilder
    private func laterGear(build: BuildSummary, member: PartyMember) -> some View {
        let later = build.gear.filter {
            $0.act > appState.selectedAct || !$0.isAvailable(at: member.level)
        }
        if !later.isEmpty {
            DisclosureGroup("Later · \(later.count)") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(later.sorted(by: {
                        ($0.act, $0.minimumLevel ?? 1, priorityRank($0.priority))
                            < ($1.act, $1.minimumLevel ?? 1, priorityRank($1.priority))
                    })) { gear in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(BG3Theme.bronzeBright)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(gear.item).font(.caption.bold())
                                Text(laterReason(gear, member: member)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.top, 5)
            }
            .font(.caption.bold())
            .padding(7)
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

    private func itemIcon(_ gear: BuildGear) -> some View {
        Group {
            if let icon = gear.icon, !icon.isEmpty, let url = URL(string: "http://127.0.0.1:8787\(icon)") {
                AsyncImage(url: url) { image in
                    image.resizable().interpolation(.high).scaledToFill()
                } placeholder: {
                    Color.clear
                }
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11)).foregroundStyle(BG3Theme.bronzeBright)
            }
        }
        .frame(width: 26, height: 26)
        .background(BG3Theme.ink.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(BG3Theme.bronze.opacity(0.6), lineWidth: 0.7))
    }

    private func pickupLine(_ gear: BuildGear) -> String {
        if let acquire = gear.acquire, !acquire.isEmpty { return acquire }
        return gear.acquisition
    }

    private func footer(build: BuildSummary, member: PartyMember) -> some View {
        Group {
            if appState.selectedAct == 1 {
                Button {
                    appState.openActOneMap(buildId: build.id, item: nil, level: member.level)
                } label: {
                    Label("Show all pickups on the map", systemImage: "map.fill").font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .assistantGlassButton().tint(BG3Theme.bronzeBright)
            } else {
                Label("The map covers Act 1 only — each item's note says where to look in Act \(appState.selectedAct).", systemImage: "map")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Cross-build conflicts

    private struct GearConflict {
        let mine: Bool  // this character has the stronger claim
        let short: String
        let detail: String
    }

    private func conflict(for gear: BuildGear, member: PartyMember) -> GearConflict? {
        if let owner = appState.gearOwner(gear), owner.id != member.id {
            return GearConflict(
                mine: false,
                short: "Equipped by \(owner.name)",
                detail: conflictDetail(gear, base: "\(owner.name) is the player-confirmed owner.")
            )
        }
        let key = normalizedItem(gear.item)
        let rivals: [(name: String, rank: Int)] = party.compactMap { other in
            guard other.id != member.id,
                  let buildId = other.buildId,
                  let otherBuild = appState.builds.first(where: { $0.id == buildId }),
                  let claim = otherBuild.gear.first(where: {
                      $0.act <= appState.selectedAct && $0.isAvailable(at: other.level) && normalizedItem($0.item) == key
                  })
            else { return nil }
            return (other.name, priorityRank(claim.priority))
        }
        guard let strongestRival = rivals.min(by: { $0.rank < $1.rank }) else { return nil }
        let myRank = priorityRank(gear.priority)
        if myRank < strongestRival.rank {
            return GearConflict(
                mine: true,
                short: "Also \(strongestRival.name)",
                detail: conflictDetail(gear, base: "\(strongestRival.name)'s build wants this too. \(member.name)'s build lists it at higher priority — \(member.name) wears it.")
            )
        }
        if myRank > strongestRival.rank {
            return GearConflict(
                mine: false,
                short: "Goes to \(strongestRival.name)",
                detail: conflictDetail(gear, base: "\(strongestRival.name)'s build lists this at higher priority.")
            )
        }
        return GearConflict(
            mine: true,
            short: "Contested — \(strongestRival.name)",
            detail: conflictDetail(gear, base: "Both \(member.name) and \(strongestRival.name) want this at the same priority.")
        )
    }

    private func conflictDetail(_ gear: BuildGear, base: String) -> String {
        guard let alternative = gear.alternative, !alternative.isEmpty else {
            return "\(base) No reviewed equivalent is available; decide ownership before spending gold."
        }
        return "\(base) Alternative: \(alternative)"
    }

    private func normalizedItem(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*x\d+$"#, with: "", options: .regularExpression).lowercased()
    }

    private func priorityRank(_ priority: String) -> Int {
        ["Required", "Core", "Upgrade", "Starter", "Support", "Defence", "Supply", "Intentional", "Optional", "Endgame"]
            .firstIndex(of: priority) ?? 99
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
