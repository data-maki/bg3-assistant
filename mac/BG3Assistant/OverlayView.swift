import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let onboardingStep = appState.onboardingStep { OnboardingCardView(step: onboardingStep) }
            else if appState.overlayExpanded { planner }
            else { PeekCardView() }
        }
        .padding(8)
        .confirmationDialog(
            appState.confirmationMessage ?? "Confirm progress",
            isPresented: Binding(
                get: { appState.pendingDisposition != nil },
                set: { if !$0 { appState.cancelPendingDisposition() } }
            )
        ) {
            if appState.pendingDisposition == .skipped {
                Button("Skip Anyway", role: .destructive, action: appState.confirmPendingDisposition)
            } else {
                Button("Mark Done", action: appState.confirmPendingDisposition)
            }
            Button("Cancel", role: .cancel, action: appState.cancelPendingDisposition)
        }
        .alert("Attach a BG3 screenshot?", isPresented: $appState.showScreenRecordingPermissionPrompt) {
            Button("Continue", action: appState.requestScreenRecordingPermission)
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Chat can capture the current BG3 window once and attach it to your next message. It excludes the overlay and is sent to OpenRouter only when you send.")
        }
    }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var expandedContentSize: CGSize {
        let panel = OverlayMetrics.expandedSize(
            for: referenceFrame,
            tab: appState.plannerTab,
            moreContextExpanded: appState.moreContextExpanded
        )
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var plannerNavigation: some View {
        HStack(spacing: 2) {
            ForEach(PlannerTab.primary) { tab in
                let selected = appState.plannerTab == tab
                Button {
                    appState.plannerTab = tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: selected ? .bold : .regular, design: .serif))
                        .foregroundStyle(selected ? BG3Theme.parchment : BG3Theme.mutedParchment.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(BG3Theme.bronze.opacity(0.22))
                                    .overlay(Capsule().stroke(BG3Theme.bronzeBright.opacity(0.52), lineWidth: 0.7))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityValue(selected ? "Selected" : "")
            }
        }
        .padding(3)
        .background(BG3Theme.ink.opacity(0.52), in: Capsule())
        .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.52), lineWidth: 0.7))
    }

    private var planner: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                PetSpriteView(size: 42)
                    .frame(width: 42, height: 42)
                    .accessibilityLabel("Twilight cleric assistant")
                DraggableArea {
                    HStack(spacing: 8) {
                        Text(plannerTitle)
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(BG3Theme.parchment).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 38)
                }
                .fixedSize(horizontal: false, vertical: true)
                Button { appState.openCurrentActMap() } label: {
                    Image(systemName: "map").frame(width: 18, height: 18)
                }
                .assistantActionButton()
                .help("Open Act \(appState.selectedAct) map")
                Button(action: appState.openChat) {
                    Image(systemName: "bubble.left.and.bubble.right").frame(width: 18, height: 18)
                }
                .assistantActionButton(accent: appState.plannerTab == .chat ? BG3Theme.bronzeBright : BG3Theme.control)
                .help("Ask about this run")
                Button(action: appState.openSettings) {
                    Image(systemName: "gearshape").frame(width: 18, height: 18)
                }
                .assistantActionButton(accent: appState.plannerTab == .settings ? BG3Theme.bronzeBright : BG3Theme.control)
                .help("Settings")
                Button(action: appState.togglePlanner) {
                    Image(systemName: "xmark").frame(width: 18, height: 18)
                }
                .assistantActionButton()
                .help("Close planner")
            }
            .fixedSize(horizontal: false, vertical: true)
            plannerNavigation

            Group {
                switch appState.plannerTab {
                case .current: NowTabView()
                case .route: RouteTabView()
                case .party: PartyTabView()
                case .loadout: LoadoutTabView()
                case .act: ActTabView()
                case .chat: ChatTabView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(width: expandedContentSize.width, height: expandedContentSize.height, alignment: .top)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.control)
        .assistantGlassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.46), radius: 20, y: 8)
    }

    /// Breadcrumb: the header says where you are; the body says what to do.
    private var plannerTitle: String {
        switch appState.plannerTab {
        case .current:
            if case .target = appState.currentGoal { return "Now ▸ Target" }
            let area = appState.currentActivityArea
            return area.isEmpty ? "Act \(appState.selectedAct) · Now" : "Now ▸ \(area)"
        case .party: return "Party"
        case .loadout: return "Loadout"
        case .settings: return "Settings"
        default: return appState.actHeaderTitle
        }
    }
}
