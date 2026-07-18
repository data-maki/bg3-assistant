import SwiftUI

/// The collapsed overlay card shown when the planner is closed.
struct PeekCardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.overlayDensity == .minimal {
            minimalPeekCard
        } else {
            focusPeekCard
        }
    }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var collapsedContentSize: CGSize {
        let panel = OverlayMetrics.collapsedSize(for: referenceFrame, density: appState.overlayDensity)
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var minimalPeekCard: some View {
        let size = collapsedContentSize
        return ZStack {
            WindowDragHandle()
            HStack(spacing: 2) {
                PetSpriteView(size: 60)
                    .frame(width: 62, height: size.height)
                    .shadow(color: .black.opacity(0.5), radius: 7, y: 3)
                Button(action: appState.showOverlayGoal) {
                    Image(systemName: "chevron.right")
                        .frame(width: 12, height: 18)
                }
                .assistantActionButton(accent: BG3Theme.bronzeBright)
                .help("Show current goal")
                .accessibilityLabel("Show current goal")
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
    }

    private var focusPeekCard: some View {
        let size = collapsedContentSize
        return VStack(spacing: 7) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(BG3Theme.ink.opacity(0.76))
                    Circle().stroke(BG3Theme.bronze, lineWidth: 2)
                    Circle().inset(by: 3).stroke(BG3Theme.gold.opacity(0.48), lineWidth: 0.7)
                    PetSpriteView(size: 74)
                }
                .frame(width: 86, height: 86)

                DraggableArea {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(appState.hasCurrentTask ? "CURRENT TASK · ACT \(appState.selectedAct)" : "ACT \(appState.selectedAct)")
                                .font(BG3Type.overline)
                                .foregroundStyle(BG3Theme.gold)
                            Spacer(minLength: 4)
                            if appState.hasGuidedGoal {
                                Text("L\(appState.currentActivityMinimumLevel)+ · \(appState.currentActivityDanger.uppercased())")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(BG3Theme.dangerColor(appState.currentActivityDanger))
                            }
                        }
                    switch appState.currentGoal {
                    case .target(let context):
                        Text(appState.currentActivityTitle)
                            .font(BG3Type.peekTitle)
                            .foregroundStyle(BG3Theme.parchment)
                            .lineLimit(2)
                        Text(GearLogic.acquireText(context.gear))
                            .font(BG3Type.caption)
                            .foregroundStyle(BG3Theme.mutedParchment)
                            .lineLimit(appState.overlayDensity == .reference ? 3 : 2)
                    case .step, .checkpoint:
                        Text(appState.currentActivityTitle)
                                .font(BG3Type.peekTitle)
                                .foregroundStyle(BG3Theme.parchment)
                                .lineLimit(2)
                            if appState.combatCardPinned {
                                ForEach(appState.combatPinLines.prefix(appState.overlayDensity == .reference ? 3 : 2), id: \.self) { line in
                                    Text(line).font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
                                }
                            } else {
                                Text("\(appState.readinessHeadline) · AVOID \(appState.currentActivityAvoid)")
                                    .font(BG3Type.caption)
                                    .foregroundStyle(BG3Theme.mutedParchment)
                                    .lineLimit(appState.overlayDensity == .reference ? 3 : 2)
                            }
                    case .laterAct:
                        Text(appState.actHeaderTitle)
                                .font(BG3Type.peekTitle)
                                .foregroundStyle(BG3Theme.parchment)
                    case .routeComplete:
                        Text(appState.currentActivityTitle)
                                .font(BG3Type.peekTitle)
                                .foregroundStyle(BG3Theme.parchment)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: appState.collapseOverlayToPet) {
                    Image(systemName: "chevron.left")
                        .frame(width: 10, height: 10)
                }
                .assistantActionButton(accent: BG3Theme.bronzeBright)
                .controlSize(.mini)
                .frame(height: 86, alignment: .top)
                .help("Collapse to companion")
                .accessibilityLabel("Collapse to companion")
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                shortcut("Route", icon: "map.fill", action: appState.showPlannerRoute)
                shortcut("Ask", icon: "bubble.left.and.text.bubble.right.fill", action: appState.openChat)
                completionShortcut
            }
        }
        .padding(9).frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.control)
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

    @ViewBuilder private var completionShortcut: some View {
        if case .target = appState.currentGoal {
            shortcut(
                "Task done",
                icon: "checkmark.seal.fill",
                tint: BG3Theme.success,
                help: "Complete the current task: \(appState.currentActivityTitle)",
                action: appState.completeGearTarget
            )
        } else if case .step(let step) = appState.currentGoal,
           let decision = step.decision {
            Menu {
                Button {
                    appState.resolveWalkthroughStep(step, outcome: decision.recommended.label)
                } label: {
                    Label("Recommended · \(decision.recommended.label)", systemImage: "checkmark.circle.fill")
                }
                ForEach(decision.alternatives, id: \.label) { option in
                    Button {
                        appState.resolveWalkthroughStep(step, outcome: option.label)
                    } label: {
                        Label(option.label, systemImage: "arrow.triangle.branch")
                    }
                }
                Divider()
                Button {
                    appState.skipCurrentActivity()
                } label: {
                    Label("Skip this step", systemImage: "forward.end")
                }
            } label: {
                shortcutLabel("Task done", icon: "checkmark.seal.fill")
            }
            .menuIndicator(.hidden)
            .assistantActionButton(accent: BG3Theme.success, prominent: true)
            .controlSize(.mini)
            .help("Complete the current task: \(appState.currentActivityTitle)")
            .accessibilityLabel("Complete current task: \(appState.currentActivityTitle)")
        } else {
            shortcut(
                "Task done",
                icon: "checkmark.seal.fill",
                disabled: !appState.hasGuidedGoal,
                tint: BG3Theme.success,
                help: "Complete the current task: \(appState.currentActivityTitle)",
                action: appState.completeCurrentActivity
            )
        }
    }

    private func shortcut(
        _ title: String,
        icon: String,
        disabled: Bool = false,
        tint: Color? = nil,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            shortcutLabel(title, icon: icon)
        }
        .assistantActionButton(accent: tint ?? BG3Theme.control, prominent: tint != nil)
        .controlSize(.mini)
        .disabled(disabled)
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }

    private func shortcutLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(BG3Type.overline)
        }
        .foregroundStyle(BG3Theme.parchment)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
    }
}
