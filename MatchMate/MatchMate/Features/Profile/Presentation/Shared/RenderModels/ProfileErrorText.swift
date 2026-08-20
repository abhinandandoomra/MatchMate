import Foundation

/// User-facing copy for every way the Profile feature can fail.
///
/// Lives in the presentation layer, not on the error types: `NetworkError` and
/// `PersistenceError` describe *what* went wrong, and how to say it to a person
/// is a UI decision. Keeping it here also makes the strings testable — a view
/// is the one place a test cannot reach.
///
/// The switch is exhaustive over `ProfileError`, so adding a failure mode is a
/// compile error here rather than silently falling through to generic copy.
enum ProfileErrorText {

    static func message(for error: ProfileError) -> String {
        switch error {
        case .network(let network): message(for: network)
        case .persistence(let persistence): message(for: persistence)
        }
    }

    static func message(for error: NetworkError) -> String {
        switch error {
        case .offline: offlineWithNothingCached
        case .timeout: "The request timed out."
        case .rateLimited: "Too many requests. Try again in a moment."
        case .server: "The server couldn't be reached."
        case .decoding: "We couldn't read the response."
        // Never shown — a cancelled load is filtered before it reaches a view.
        case .cancelled: ""
        }
    }

    static func message(for error: PersistenceError) -> String {
        switch error {
        case .unavailable: "Your saved matches couldn't be opened."
        case .notFound: profileUnavailable
        case .operationFailed: "Couldn't save your change."
        }
    }

    // Copy the views need without an error to hand.
    /// Shown *over* cached content, so it can promise what is on screen.
    static let offlineWithCache = "You're offline. Showing saved matches."

    /// Shown when the failure is total — nothing cached to fall back on, so it
    /// must not promise saved matches that do not exist.
    static let offlineWithNothingCached = "You're offline. Connect to load matches."
    static let profileUnavailable = "That profile is no longer available."
    static let loadFailedTitle = "Couldn't load matches"
    static let startupFailedTitle = "Couldn't start MatchMate"
}
