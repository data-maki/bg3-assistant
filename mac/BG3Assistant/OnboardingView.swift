import SwiftUI

/// One page of the welcome tour, rendered by the overlay panel in place of
/// the planner or peek card until the tour is finished or skipped.
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
            VStack(alignment: .leading, spacing: 8) {
                ForEach(step.facts, id: \.text) { fact in
                    FactRow(glyph: fact.glyph, tint: tint(for: fact.role), text: fact.text)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bg3InsetSurface()
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
                    Text("WELCOME TOUR")
                        .font(BG3Type.overline)
                        .foregroundStyle(BG3Theme.gold)
                    Text("Step \(step.stepNumber) of \(OnboardingStep.allCases.count)")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: appState.skipOnboarding) {
                Image(systemName: "xmark").frame(width: 18, height: 18)
            }
            .assistantActionButton()
            .help("Skip the tour")
            .accessibilityLabel("Skip the welcome tour")
        }
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { candidate in
                Capsule()
                    .fill(candidate == step ? BG3Theme.gold : BG3Theme.mutedParchment.opacity(0.35))
                    .frame(width: candidate == step ? 18 : 6, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.stepNumber) of \(OnboardingStep.allCases.count)")
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
            }
            Spacer(minLength: 0)
            if let handoff = step.handoff {
                Button(handoff.title) {
                    appState.finishOnboarding(opening: handoff)
                }
                .assistantActionButton(accent: BG3Theme.bronzeBright)
                .help("Finish the tour there")
            }
            Button {
                appState.advanceOnboarding()
            } label: {
                HStack(spacing: 4) {
                    Text(step.primaryActionTitle)
                    if !step.isLast { Image(systemName: "chevron.right") }
                }
            }
            .assistantActionButton(accent: BG3Theme.success, prominent: true)
            .accessibilityLabel(step.primaryActionTitle)
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
