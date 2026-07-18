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

/// How this run enters the assistant: from the Nautiloid beach, or adopted
/// mid-run with a catch-up step that syncs the route ledger.
enum OnboardingMode {
    case fresh
    case midRun
}

/// The first-run intake wizard, shown by the overlay in place of the planner
/// or peek card until finished or skipped. Unlike the old fact tour, every
/// step captures run state; teaching moved to one-time hints. Pure model
/// (Foundation only) so the flow is verifiable without XCTest.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case party
    case catchUp
    case ready

    /// Bump after a UX overhaul to re-show the wizard once. Finishing or
    /// skipping records this in `AssistantSettings.onboardingSeenVersion`.
    static let version = 2

    static func steps(for mode: OnboardingMode) -> [OnboardingStep] {
        mode == .midRun ? [.welcome, .party, .catchUp, .ready] : [.welcome, .party, .ready]
    }

    static func stepCount(for mode: OnboardingMode) -> Int { steps(for: mode).count }

    func next(for mode: OnboardingMode) -> OnboardingStep? {
        let steps = Self.steps(for: mode)
        guard let index = steps.firstIndex(of: self), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    func previous(for mode: OnboardingMode) -> OnboardingStep? {
        let steps = Self.steps(for: mode)
        guard let index = steps.firstIndex(of: self), index > 0 else { return nil }
        return steps[index - 1]
    }

    func stepNumber(for mode: OnboardingMode) -> Int {
        (Self.steps(for: mode).firstIndex(of: self) ?? 0) + 1
    }

    var isFirst: Bool { self == .welcome }

    func isLast(for mode: OnboardingMode) -> Bool { next(for: mode) == nil }

    var title: String {
        switch self {
        case .welcome: "Well Met, Adventurer"
        case .party: "Who Is at Your Table?"
        case .catchUp: "Where Are You?"
        case .ready: "Ready to Adventure"
        }
    }

    var intro: String {
        switch self {
        case .welcome:
            "Your Honor Mode companion floats above Baldur's Gate 3. Two quick questions and its advice matches your run — not a default one."
        case .party:
            "Set who is actually in the party and their level. Fight readiness and danger warnings key off your lowest active level."
        case .catchUp:
            "Pick the last landmark you finished. Everything before it is marked caught up so the route resumes exactly where you are."
        case .ready:
            "Everything is saved locally on this Mac — no account, no sign-in. The guide works fully offline."
        }
    }

    /// Short teaching facts for the final card; everything else is captured
    /// state, not reading.
    var facts: [OnboardingFact] {
        switch self {
        case .ready: [
            .action("Hold Option-Space to peek at the current task while playing."),
            .action("The chevron on the card — or the menu-bar shield — opens the full planner."),
            .insight("The map button opens an interactive act map in your browser, synced to this run."),
            .reward("Ask anything in CHAT; answers cite the guide they came from."),
        ]
        default: []
        }
    }

    /// nil = the step advances through its own controls (welcome's fork).
    func primaryActionTitle(for mode: OnboardingMode) -> String? {
        switch self {
        case .welcome: nil
        case .party: "Continue"
        case .catchUp: "Catch Up & Continue"
        case .ready: "Start Adventuring"
        }
    }
}

/// Bulk mid-run adoption of the walkthrough ledger.
enum CatchUp {
    /// The ledger after marking every still-pending step up to and including
    /// the landmark's owning step as `caughtUp`. Existing entries are
    /// preserved — the player's explicit history always wins. Returns nil
    /// when no walkthrough step owns the checkpoint.
    static func ledger(
        markingThrough checkpointId: String,
        walkthrough: [WalkthroughStep],
        existing: [String: CheckpointDisposition]
    ) -> [String: CheckpointDisposition]? {
        guard let landmark = walkthrough.first(where: { $0.checkpointId == checkpointId }) else { return nil }
        var ledger = existing
        for step in walkthrough where step.order <= landmark.order && ledger[step.id] == nil {
            ledger[step.id] = .caughtUp
        }
        return ledger
    }

    /// How many steps `ledger(markingThrough:)` would newly mark — drives the
    /// wizard's confirmation caption.
    static func markedCount(
        markingThrough checkpointId: String,
        walkthrough: [WalkthroughStep],
        existing: [String: CheckpointDisposition]
    ) -> Int {
        guard let landmark = walkthrough.first(where: { $0.checkpointId == checkpointId }) else { return 0 }
        return walkthrough.count { $0.order <= landmark.order && existing[$0.id] == nil }
    }
}
