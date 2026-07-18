import Foundation

/// One-time coach marks, shown at the moment a surface first becomes
/// relevant instead of front-loaded in the intake wizard. Raw values persist
/// in `AssistantSettings.seenHints`, so they must stay stable. Rules live in
/// `AppState.maybeShowHint`: never during onboarding or a pinned fight, at
/// most one per session, dismissed forever once acknowledged.
enum HintID: String, CaseIterable {
    /// First status refresh with BG3 detected while collapsed.
    case peekBasics
    /// First time the planner opens.
    case plannerMap
    /// First time the current goal is a fight checkpoint while collapsed.
    case fightTools

    var text: String {
        switch self {
        case .peekBasics:
            "Hold Option-Space to peek while playing. Drag the card anywhere — it remembers its spot."
        case .plannerMap:
            "The map button opens an interactive act map in your browser, synced to this run."
        case .fightTools:
            "Right-click the card to snooze warnings, mute a checkpoint, or change density."
        }
    }
}
