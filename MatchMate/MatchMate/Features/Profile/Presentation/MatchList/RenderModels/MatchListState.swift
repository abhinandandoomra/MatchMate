import Foundation

/// What the match list is doing, as one closed set.
///
/// Replaces four booleans (`isLoadingPage`, `pageError`, `isFirstLoad`,
/// `hasContent`) whose combinations included states that cannot actually occur.
/// The old full-screen-error condition was a four-term boolean expression —
/// reliable proof that a state enum was missing. The view now switches once,
/// exhaustively, and cannot render a combination the ViewModel never produces.
enum MatchListState: Equatable, Sendable {
    /// Nothing to show yet and work in flight.
    case loading
    /// Loaded successfully, but the feed is genuinely empty.
    case empty
    /// The first load failed with nothing cached to fall back on.
    case failed(message: String)
    /// Content to show, plus whatever the paging footer should say.
    case loaded(rows: [MatchRowUIModel], footer: MatchListFooter)
}

/// Paging feedback belongs at the bottom of the list, never over it: cached
/// content stays readable while the next page loads or fails.
enum MatchListFooter: Equatable, Sendable {
    case idle
    case loadingMore
    case failed(message: String)
}
