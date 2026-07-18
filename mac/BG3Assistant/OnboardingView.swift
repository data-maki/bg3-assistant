import SwiftUI

/// One page of the intake wizard, rendered by the overlay panel in place of
/// the planner or peek card until the wizard is finished or skipped.
struct OnboardingCardView: View {
    @EnvironmentObject private var appState: AppState
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(step.title)
                .font(BG3Type.pageTitle)
                .foregroundStyle(BG3Theme.parchment)
            Text(step.intro)
                .font(BG3Type.body)
                .foregroundStyle(BG3Theme.mutedParchment)
                .fixedSize(horizontal: false, vertical: true)
            stepContent
            Spacer(minLength: 0)
            progressDots
            footer
        }
        .padding(14)
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        .foregroundStyle(BG3Theme.parchment)
        .colorScheme(.dark)
        .tint(BG3Theme.control)
        .assistantGlassSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.46), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var mode: OnboardingMode { appState.onboardingMode }

    private var referenceFrame: CGRect {
        appState.gameWindowFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var contentSize: CGSize {
        let panel = OverlayMetrics.onboardingSize(for: referenceFrame)
        return CGSize(width: panel.width - 16, height: panel.height - 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            PetSpriteView(size: 46)
                .frame(width: 46, height: 46)
                .accessibilityLabel("Twilight cleric assistant")
            DraggableArea {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SETUP")
                        .font(BG3Type.overline)
                        .foregroundStyle(BG3Theme.gold)
                    Text("Step \(step.stepNumber(for: mode)) of \(OnboardingStep.stepCount(for: mode))")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: appState.skipOnboarding) {
                Image(systemName: "xmark").frame(width: 18, height: 18)
            }
            .assistantActionButton()
            .help("Skip setup")
            .accessibilityLabel("Skip setup")
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: welcomeContent
        case .party: partyContent
        case .catchUp: catchUpContent
        case .ready: readyContent
        }
    }

    // MARK: - Welcome (the fork)

    private var welcomeContent: some View {
        VStack(spacing: 8) {
            forkButton(
                icon: "figure.walk.departure",
                title: "Starting a fresh honor run",
                detail: "Act 1, level 1 — routed from the Nautiloid beach.",
                action: appState.chooseFreshRun
            )
            forkButton(
                icon: "map",
                title: "Already mid-run",
                detail: "Tell me where you are; the route and warnings catch up to you.",
                action: appState.chooseMidRun
            )
        }
    }

    private func forkButton(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BG3Theme.gold)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BG3Type.rowTitle)
                        .foregroundStyle(BG3Theme.parchment)
                    Text(detail)
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .bg3InsetSurface(accent: BG3Theme.bronzeBright)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    // MARK: - Party

    private var partyContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Everyone's level")
                    .font(BG3Type.rowTitle)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { appState.lowestPartyLevel },
                        set: { appState.setAllPartyLevels($0) }
                    ),
                    in: 1...12
                ) {
                    Text("L\(appState.lowestPartyLevel)")
                        .font(BG3Type.rowTitle)
                        .foregroundStyle(BG3Theme.gold)
                        .frame(minWidth: 30)
                }
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(sortedRoster) { member in PartyRosterRow(member: member) }
                }
                .padding(.trailing, 6)
            }
            FactRow(
                glyph: "◆", tint: BG3Theme.gold,
                text: "Readiness and danger warnings key off level \(appState.lowestPartyLevel). Builds can be assigned anytime in PARTY."
            )
        }
    }

    private var sortedRoster: [PartyMember] {
        appState.roster.sorted { lhs, rhs in
            let lhsRank = lhs.rosterStatus.sortRank
            let rhsRank = rhs.rosterStatus.sortRank
            return lhsRank == rhsRank
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhsRank < rhsRank
        }
    }

    // MARK: - Catch-up

    private var catchUpContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("Act")
                    .font(BG3Type.rowTitle)
                ForEach(1...3, id: \.self) { act in
                    let selected = appState.selectedAct == act
                    Button("\(act)") { appState.selectOnboardingAct(act) }
                        .assistantActionButton(
                            accent: selected ? BG3Theme.gold : BG3Theme.control,
                            prominent: selected
                        )
                        .accessibilityLabel("Act \(act)")
                        .accessibilityValue(selected ? "Selected" : "")
                }
                Spacer()
            }
            if guideStillLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the Act \(appState.selectedAct) route…")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        landmarkRow(id: nil, name: "Start of the act", note: "Nothing to mark")
                        ForEach(sortedRoute) { checkpoint in
                            landmarkRow(id: checkpoint.id, name: checkpoint.name, note: checkpoint.area)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
            FactRow(glyph: "◆", tint: BG3Theme.gold, text: catchUpCaption)
        }
    }

    private var guideStillLoading: Bool {
        appState.loadedGuideAct != appState.selectedAct
    }

    private var sortedRoute: [RouteCheckpoint] {
        appState.route.sorted { $0.routeOrder < $1.routeOrder }
    }

    private func landmarkRow(id: String?, name: String, note: String) -> some View {
        let selected = appState.onboardingCatchUpCheckpointId == id
        return Button {
            appState.onboardingCatchUpCheckpointId = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? BG3Theme.gold : BG3Theme.mutedParchment)
                Text(name)
                    .font(BG3Type.body)
                    .foregroundStyle(BG3Theme.parchment)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(selected ? "you are here" : note)
                    .font(BG3Type.caption)
                    .foregroundStyle(selected ? BG3Theme.gold : BG3Theme.mutedParchment)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8).fill(BG3Theme.bronze.opacity(0.18))
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private var catchUpCaption: String {
        guard let checkpointId = appState.onboardingCatchUpCheckpointId else {
            return "Starting Act \(appState.selectedAct) from the beginning — nothing is marked."
        }
        let count = CatchUp.markedCount(
            markingThrough: checkpointId,
            walkthrough: appState.walkthrough,
            existing: appState.run.walkthroughProgress ?? [:]
        )
        return "\(count) earlier step\(count == 1 ? "" : "s") will be marked caught up — kept distinct from steps you complete with the assistant."
    }

    // MARK: - Ready

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(step.facts, id: \.text) { fact in
                    FactRow(glyph: fact.glyph, tint: tint(for: fact.role), text: fact.text)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bg3InsetSurface()
            Toggle(isOn: $appState.onboardingEnableLoginItem) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start at login")
                        .font(BG3Type.rowTitle)
                    Text("The assistant waits in the menu bar so the companion appears whenever BG3 opens.")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.steps(for: mode), id: \.rawValue) { candidate in
                Capsule()
                    .fill(candidate == step ? BG3Theme.gold : BG3Theme.mutedParchment.opacity(0.35))
                    .frame(width: candidate == step ? 18 : 6, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.stepNumber(for: mode)) of \(OnboardingStep.stepCount(for: mode))")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !step.isFirst {
                Button {
                    appState.regressOnboarding()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .assistantActionButton()
                .accessibilityLabel("Back to previous step")
            } else {
                Button("Skip — explore with defaults", action: appState.skipOnboarding)
                    .buttonStyle(.plain)
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .accessibilityLabel("Skip setup and explore with defaults")
            }
            Spacer(minLength: 0)
            if let title = step.primaryActionTitle(for: mode) {
                Button {
                    if step == .catchUp { appState.applyCatchUpAndAdvance() }
                    else { appState.advanceOnboarding() }
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                        if !step.isLast(for: mode) { Image(systemName: "chevron.right") }
                    }
                }
                .assistantActionButton(accent: BG3Theme.success, prominent: true)
                .disabled(step == .catchUp && guideStillLoading)
                .accessibilityLabel(title)
            }
        }
    }

    private func tint(for role: OnboardingFactRole) -> Color {
        switch role {
        case .action: BG3Theme.control
        case .insight: BG3Theme.gold
        case .reward: BG3Theme.success
        }
    }
}
