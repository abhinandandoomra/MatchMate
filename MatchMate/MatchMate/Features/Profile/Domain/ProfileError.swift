import Foundation

/// Everything the Profile feature can fail with, as a closed set.
///
/// Wrapping rather than erasing to `any Error` is what keeps failure handling
/// exhaustive: the presentation mapper switches over these two cases and the
/// compiler reports any it misses. An `any Error` would need a `default:`
/// branch — a silent catch-all where a new failure mode disappears into
/// generic copy instead of being noticed.
enum ProfileError: Error, Equatable, Sendable {
    case network(NetworkError)
    case persistence(PersistenceError)
}
