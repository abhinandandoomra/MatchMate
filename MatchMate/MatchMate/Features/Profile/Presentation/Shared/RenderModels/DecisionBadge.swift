import Foundation

/// Semantic meaning of a decided state. The view maps a tone to a colour; it
/// never decides what a status *means*.
enum DecisionTone: Sendable, Equatable {
    case positive, negative
}

/// Everything the decided-state pill renders, as data.
///
/// Produced by the mappers alongside every other piece of user-facing copy, so
/// the strings a person reads — and a VoiceOver user hears — are unit-tested
/// like the rest of the app's text, instead of living in a view that no test
/// can reach.
struct DecisionBadge: Sendable, Equatable {
    let title: String
    let symbolName: String
    let tone: DecisionTone
    let accessibilityHint: String

    /// `nil` for `.pending`, which is what makes the undecided state
    /// unrepresentable in the pill: there is no badge to build, so the pill
    /// cannot be constructed for a profile that has not been decided.
    static func make(for status: DecisionStatus) -> DecisionBadge? {
        switch status {
        case .pending:
            nil
        case .accepted:
            DecisionBadge(
                title: "Accepted",
                symbolName: "checkmark.circle.fill",
                tone: .positive,
                accessibilityHint: "Double tap to undo and return this match to undecided"
            )
        case .declined:
            DecisionBadge(
                title: "Declined",
                symbolName: "xmark.circle.fill",
                tone: .negative,
                accessibilityHint: "Double tap to undo and return this match to undecided"
            )
        }
    }

    /// What VoiceOver announces for the row as a whole.
    static func description(for status: DecisionStatus) -> String {
        switch status {
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .pending: "No decision yet"
        }
    }
}
