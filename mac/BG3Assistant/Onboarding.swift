import Foundation

/// Semantic role of a tour fact; the card view maps roles to theme tints.
enum OnboardingFactRole {
    case action
    case insight
    case reward
}

struct OnboardingFact: Equatable {
    let glyph: String
    let role: OnboardingFactRole
    let text: String

    static func action(_ text: String) -> OnboardingFact { .init(glyph: "→", role: .action, text: text) }
    static func insight(_ text: String) -> OnboardingFact { .init(glyph: "◆", role: .insight, text: text) }
    static func reward(_ text: String) -> OnboardingFact { .init(glyph: "★", role: .reward, text: text) }
}

/// Planner surface a tour step can hand off to when it finishes early.
enum OnboardingHandoff {
    case party
    case settings

    var title: String {
        switch self {
        case .party: "Open Party Tab"
        case .settings: "Open Settings"
        }
    }
}

/// The first-run welcome tour, shown by the overlay in place of the planner
/// or peek card until finished or skipped. Pure model (Foundation only) so
/// the flow is verifiable without XCTest.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case peek
    case planner
    case party
    case chat

    /// Bump after a UX overhaul to re-show the tour once. Finishing or
    /// skipping records this in `AssistantSettings.onboardingSeenVersion`.
    static let version = 1

    var isFirst: Bool { self == Self.allCases.first }
    var isLast: Bool { self == Self.allCases.last }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var stepNumber: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .welcome: "Well Met, Adventurer"
        case .peek: "The Peek Card"
        case .planner: "The Planner"
        case .party: "Make It Your Party"
        case .chat: "An Optional AI Seer"
        }
    }

    var intro: String {
        switch self {
        case .welcome:
            "This is your Honor Mode companion. It floats above Baldur's Gate 3 and keeps the run on the rails."
        case .peek:
            "Collapsed, the assistant shows only what matters right now."
        case .planner:
            "The chevron on the peek card — or the menu-bar shield — opens the full planner."
        case .party:
            "Tell the assistant who you are actually playing so its advice matches your table."
        case .chat:
            "Add an OpenRouter API key in Settings to unlock chat about your run."
        }
    }

    var facts: [OnboardingFact] {
        switch self {
        case .welcome: [
            .action("The overlay appears automatically whenever BG3 is running."),
            .insight("Advice comes from a curated act guide: route, fights, party, and gear."),
            .reward("Everything is saved locally on this Mac — no account, no sign-in."),
        ]
        case .peek: [
            .action("Your current task, its danger level, and what to avoid — at a glance."),
            .action("Hold Option-Space to peek while playing; release to tuck it away."),
            .action("Drag the card anywhere; it remembers its place."),
            .insight("Right-click the card for density (Minimal · Focus · Reference) and snoozing warnings."),
        ]
        case .planner: [
            .action("NOW recommends the next safe step; mark it done or skip it honestly."),
            .action("ROUTE, PARTY, LOADOUT, and ACT hold the walkthrough, roster, and gear plan."),
            .insight("The map button opens an interactive act map in your browser, synced to this run."),
        ]
        case .party: [
            .action("Set members, levels, and builds in the PARTY tab."),
            .insight("Fight readiness and danger warnings key off your lowest party level."),
            .reward("With builds chosen, the LOADOUT tab plans who carries every notable item."),
        ]
        case .chat: [
            .action("Ask anything in CHAT; answers cite the guide they came from."),
            .action("Attach a BG3 screenshot to ask about exactly what is on screen."),
            .insight("No key? Everything else still works — the guide is fully local."),
        ]
        }
    }

    var primaryActionTitle: String { isLast ? "Start Adventuring" : "Continue" }

    var handoff: OnboardingHandoff? {
        switch self {
        case .party: .party
        case .chat: .settings
        default: nil
        }
    }
}
