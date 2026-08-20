import Foundation

/// Everything the local store can fail with. No user-facing copy, by design.
enum PersistenceError: Error, Equatable, Sendable {
    /// The store could not be opened — corrupt, migration-incompatible, or no
    /// room on disk. Fatal for the session, not for a single operation.
    case unavailable
    /// No row matches the key the caller asked for.
    case notFound
    /// The context refused a read or a write.
    case operationFailed
}
