import SwiftUI

/// One item, fully explained: what it does, how to get it, who else wants
/// it, and — when interactive — what to do about it. Shown pinned or as a
/// hover preview in the Loadout drawer and as a pushed page from Route
/// pickups, so every surface describes gear the same way.
struct GearDetailView: View {
    @EnvironmentObject private var appState: AppState
    let gear: BuildGear
    let member: PartyMember
    var showsActions = true

    private var equipped: Bool { appState.gearIsEquipped(gear, by: member) }
    private var owner: PartyMember? { appState.gearOwner(gear) }
    private var targeted: Bool { appState.gearIsTargeted(gear, for: member) }
    private var conflict: GearConflict? { appState.gearConflict(for: gear, member: member) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let effect = gear.effect, !effect.isEmpty {
                FactRow(glyph: "★", tint: BG3Theme.gold, text: effect)
            }
            FactRow(glyph: "→", tint: BG3Theme.parchment, text: GearLogic.acquireText(gear))
            if let requirement = gear.requirement, !requirement.isEmpty {
                FactRow(glyph: "◆", tint: BG3Theme.mutedParchment, text: requirement, secondary: true)
            }
            if let conflict {
                FactRow(glyph: "⚠", tint: BG3Theme.warning, text: "\(conflict.short) — \(conflict.detail)", secondary: true)
            }
            if showsActions { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            GearItemIcon(gear: gear)
            VStack(alignment: .leading, spacing: 1) {
                Text(gear.item)
                    .font(BG3Type.rowTitle)
                    .foregroundStyle(BG3Theme.parchment)
                    .lineLimit(1)
                Text("\(member.name) · \(gear.slot) · Act \(gear.act)")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if targeted {
                StatusChip(text: "target", tint: BG3Theme.gold, filled: true)
            } else if equipped {
                StatusChip(text: "equipped", tint: BG3Theme.success)
            } else if let owner, owner.id != member.id {
                StatusChip(text: owner.name, tint: BG3Theme.warning)
            } else if let planned = appState.plannedOwner(ofItemKey: gear.itemKey), planned.id != member.id {
                StatusChip(text: "→ \(planned.name)", tint: BG3Theme.warning)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if targeted {
                Button {
                    appState.clearGearTarget()
                } label: {
                    Label("Clear target", systemImage: "scope")
                }
                .assistantActionButton(accent: BG3Theme.warning)
            } else if !equipped {
                Button {
                    appState.setGearTarget(gear, for: member)
                } label: {
                    Label("Set as target", systemImage: "scope")
                }
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
                .disabled(gear.act != appState.selectedAct || member.buildId == nil)
                .help(gear.act == appState.selectedAct
                    ? "Make this the current goal on the Now page"
                    : "Act \(gear.act) item — it can become a target in Act \(gear.act)")
            }
            if gear.isMapObjective {
                Button {
                    appState.toggleGear(gear, for: member)
                } label: {
                    if equipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill")
                    } else if let owner, owner.id != member.id {
                        Label("Take from \(owner.name)", systemImage: "arrow.left.arrow.right")
                    } else {
                        Label("Mark equipped", systemImage: "circle")
                    }
                }
                .assistantActionButton(accent: equipped ? BG3Theme.success : BG3Theme.control)
                .help(equipped ? "Remove the confirmed assignment" : "Confirm \(member.name) has this")
            }
            if !equipped,
               let planned = appState.plannedOwner(ofItemKey: gear.itemKey),
               planned.id != member.id {
                Button {
                    appState.setGearAssignmentOverride(gear, to: member)
                } label: {
                    Label("Give to \(member.name)", systemImage: "person.fill.checkmark")
                }
                .assistantActionButton(accent: BG3Theme.warning)
                .help("Override the automatic assignment — \(planned.name)'s build requested it first")
            }
            if gear.isMapObjective, gear.act == appState.selectedAct, let buildId = member.buildId {
                Button {
                    appState.openCurrentActMap(buildId: buildId, item: gear.item, level: member.level)
                } label: {
                    Label("Map", systemImage: "mappin.and.ellipse")
                }
                .assistantActionButton()
                .help("Show the pickup on the map")
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }
}

/// Item icon with a visible fallback. Bundled guide icons use backend-relative
/// paths, while imported builds may provide an absolute remote URL.
struct GearItemIcon: View {
    let gear: BuildGear
    var size: CGFloat = 26
    var borderColor: Color = BG3Theme.bronze

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().interpolation(.high).scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(BG3Theme.ink.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(borderColor.opacity(0.75), lineWidth: 0.8))
        .accessibilityHidden(true)
    }

    private var remoteURL: URL? {
        guard let icon = gear.icon,
              let url = URL(string: icon),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private var bundledImage: NSImage? {
        guard let icon = gear.icon, remoteURL == nil else { return nil }
        let filename = URL(fileURLWithPath: icon).lastPathComponent
        guard !filename.isEmpty else { return nil }
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/ItemIcons", directoryHint: .isDirectory)
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "ItemIcons/\(filename)"),
            sourceDirectory.appending(path: filename),
        ].compactMap { $0 }
        return candidates.lazy
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap(NSImage.init(contentsOf:))
            .first
    }

    private var fallback: some View {
        Image(systemName: LoadoutSlot.classify(gear.slot, item: gear.item).icon)
            .font(.system(size: size * 0.42))
            .foregroundStyle(BG3Theme.bronzeBright)
    }
}
