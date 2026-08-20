import Foundation

/// What the user asked for, in the view layer's own vocabulary.
///
/// Views emit intent, never domain state: a card cannot express
/// `DecisionStatus.accepted`, only "the user tapped Accept". Translating that
/// into a status is the ViewModel's job, which keeps `DecisionStatus` — and the
/// domain generally — out of the view layer entirely.
///
/// `undo` is explicit rather than inferred. Previously the pill re-applied the
/// status it already showed and relied on a toggle to invert it, which meant a
/// view had to know that rule.
enum DecisionIntent: Sendable, Equatable {
    case accept
    case decline
    case undo
}
