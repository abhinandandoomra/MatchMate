import Foundation

/// The local data source: CRUD over cached profiles.
///
/// Keyed by `login.uuid` rather than `PersistentIdentifier`, and speaking only
/// in domain values, so no SwiftData type crosses this line — which is what
/// lets every ViewModel and repository test run without a `ModelContainer`.
protocol ProfileStore: Sendable {

    // MARK: - Reads

    /// Every cached profile, in stable API order.
    func profiles() async throws(PersistenceError) -> [Profile]

    /// The highest page persisted, from which the paging cursor is derived.
    func maxSourcePage() async throws(PersistenceError) -> Int?

    func isEmpty() async throws(PersistenceError) -> Bool

    // MARK: - Writes

    /// Inserts new profiles and refreshes API-owned fields on existing ones.
    /// A user's decision is never touched.
    ///
    /// Returns the rows **as persisted**, which is not the same as what was
    /// passed in: an existing row keeps its decision (R-1), so echoing back the
    /// argument would report `.pending` for a profile the user had already
    /// accepted. Handing back the stored truth lets a caller update in place
    /// without re-reading the table.
    @discardableResult
    func upsert(_ profiles: [Profile]) async throws(PersistenceError) -> [Profile]

    /// Returns the row as persisted, so a caller can update one element instead
    /// of re-reading the whole table. The store stays the authority on the
    /// resulting state — notably `decidedAt` — so the two cannot drift.
    @discardableResult
    func setStatus(_ status: DecisionStatus, uuid: String) async throws(PersistenceError) -> Profile

    /// Returns the updated row, or `nil` if no profile matches — a portrait
    /// arriving for an evicted profile is not an error.
    @discardableResult
    func saveImage(_ data: Data, uuid: String) async throws(PersistenceError) -> Profile?
}
