import Foundation

/// A fully formatted, view-ready description of one profile.
///
/// The detail screen renders `sections` generically, so adding a field is a
/// change to the mapper alone — the view never needs to know a field exists.
struct ProfileDetailUIModel: Sendable, Equatable {

    struct Field: Sendable, Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Section: Sendable, Equatable, Identifiable {
        let title: String
        let fields: [Field]
        var id: String { title }
    }

    let uuid: String
    let fullName: String
    /// e.g. `"33 · Van, Turkey"`
    let ageLine: String
    /// `nil` while undecided — see `MatchRowUIModel.decision`.
    let decision: DecisionBadge?
    /// A write is in flight; controls are inert until it lands.
    let isBusy: Bool
    let imageData: Data?
    let initials: String
    let sections: [Section]
}
