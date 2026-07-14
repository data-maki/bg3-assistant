import SwiftUI

/// The collapsed overlay card shown when the planner is closed.
struct PeekCardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.effectiveOverlayDensity == .minimal {
            minimalPeekCard
        } else {
            focusPeekCard
        }
    }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var collapsedContentSize: CGSize {
        let panel = OverlayMetrics.collapsedSize(for: referenceFrame, density: appState.effectiveOverlayDensity)
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var minimalPeekCard: some View {
        let size = collapsedContentSize
        return ZStack {
            WindowDragHandle()
            Button(action: appState.showPlannerNow) {
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(BG3Theme.ink.opacity(0.82))
                        Circle().stroke(BG3Theme.dangerColor(appState.currentActivityDanger), lineWidth: 2)
                        PetSpriteView(size: 54)
                    }
                    .frame(width: 62, height: 62)
                    Text(appState.assistantPhase.rawValue)
                        .font(.system(size: 8, weight: .heavy, design: .serif))
                        .foregroundStyle(BG3Theme.gold)
                }
                .frame(width: 78, height: size.height)
            }
            .buttonStyle(.plain)
        }
        .frame(width: size.width, height: size.height)
        .assistantGlassSurface(cornerRadius: 18)
        .contextMenu { densityMenu }
        .help("Hold Option-Space to peek · click for planner")
    }

    private var focusPeekCard: some View {
        let size = collapsedContentSize
        return VStack(spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(BG3Theme.ink.opacity(0.76))
                    Circle().stroke(BG3Theme.bronze, lineWidth: 2)
                    Circle().inset(by: 3).stroke(BG3Theme.gold.opacity(0.48), lineWidth: 0.7)
                    PetSpriteView(size: 55)
                }
                .frame(width: 64, height: 64)

                DraggableArea {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(appState.telemetryActive ? "LIVE • \(appState.assistantPhase.rawValue)" : appState.assistantPhase.rawValue)
                                .font(.system(size: 8.5, weight: .heavy, design: .serif))
                                .foregroundStyle(BG3Theme.gold)
                            Spacer(minLength: 4)
                            if appState.currentWalkthroughStep != nil || appState.currentCheckpoint != nil {
                                Text("L\(appState.currentActivityMinimumLevel)+ · \(appState.currentActivityDanger.uppercased())")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(BG3Theme.dangerColor(appState.currentActivityDanger))
                            }
                        }
                    if appState.currentWalkthroughStep != nil || appState.currentCheckpoint != nil {
                        Text(appState.currentActivityTitle)
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment)
                                .lineLimit(1)
                            if appState.combatCardPinned {
                                ForEach(appState.combatPinLines.prefix(appState.effectiveOverlayDensity == .reference ? 3 : 2), id: \.self) { line in
                                    Text(line).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
                                }
                            } else {
                                Text("\(appState.readinessHeadline) · AVOID \(appState.currentActivityAvoid)")
                                    .font(.system(size: 9.2, weight: .semibold))
                                    .foregroundStyle(BG3Theme.mutedParchment)
                                    .lineLimit(appState.effectiveOverlayDensity == .reference ? 3 : 2)
                            }
                    } else {
                        Text(appState.route.isEmpty ? "Guide offline — open the app" : "Act 1 complete")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundStyle(BG3Theme.parchment)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                shortcut("Plan", icon: "list.clipboard.fill", action: appState.showPlannerNow)
                shortcut("Talk", icon: "quote.bubble.fill", disabled: appState.currentDialogueStep == nil, action: appState.openDialogue)
                shortcut("Ask", icon: "bubble.left.and.text.bubble.right.fill", action: appState.openChat)
                shortcut("Done", icon: "checkmark.seal.fill", disabled: appState.currentWalkthroughStep == nil && appState.currentCheckpoint == nil, tint: BG3Theme.success, action: appState.completeCurrentActivity)
            }
        }
        .padding(9).frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.gold)
        .assistantGlassSurface(cornerRadius: 14)
        .shadow(color: .black.opacity(0.42), radius: 14, y: 6)
        .contextMenu {
            Button("Open chat", action: appState.openChat)
            Button("Snooze warnings 10 minutes", action: appState.snoozeWarnings)
            Button(appState.isCurrentCheckpointMuted ? "Unmute checkpoint" : "Mute checkpoint", action: appState.toggleMuteCurrentCheckpoint)
            if appState.combatCardPinned { Button("Unpin fight", action: appState.unpinFight) }
            Divider()
            densityMenu
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var densityMenu: some View {
        Menu("Overlay density") {
            ForEach(OverlayDensity.allCases) { density in
                Button {
                    appState.overlayDensity = density
                } label: {
                    Label(density.rawValue, systemImage: appState.overlayDensity == density ? "checkmark" : "circle")
                }
            }
        }
    }

    private func shortcut(_ title: String, icon: String, disabled: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .serif))
            }
            .foregroundStyle(BG3Theme.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .assistantGlassButton()
        .controlSize(.mini)
        .tint(tint ?? BG3Theme.bronzeBright)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}
