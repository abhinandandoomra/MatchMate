import Foundation

/// Everything one row of the match list needs to draw itself.
///
/// The view layer never sees a `Profile`: keeping the row model flat and
/// `Equatable` means SwiftUI can diff rows cheaply, and the mapping stays a
/// pure function that is trivial to unit-test without a repository.
struct MatchRowUIModel: Sendable, Identifiable, Equatable {
    let id: String
    let fullName: String
    /// e.g. `"33 · Van, Turkey"`
    let subtitle: String
    /// `nil` while undecided — the presence of a badge *is* the decided state.
    let decision: DecisionBadge?
    /// A write is in flight for this profile; controls are inert until it lands.
    let isBusy: Bool
    /// What VoiceOver announces for the row as a whole.
    let statusDescription: String
    let imageData: Data?
    /// e.g. `"NA"` — drawn locally when there are no portrait bytes.
    let initials: String
}
