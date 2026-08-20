import Foundation
import SwiftData

/// The production `ProfileStore`: one SwiftData `ModelContext` on its own actor.
///
/// `@ModelActor` synthesises the stored `modelContainer`/`modelExecutor`, the
/// `init(modelContainer:)` initialiser, and the custom executor that pins every
/// isolated member to the context's own queue. That is what makes the whole class
/// safe under Swift 6 strict concurrency: `ModelContext` and `ProfileEntity` are
/// not `Sendable`, so all access to them has to happen in one place.
///
/// The rule that keeps it sound: **`ProfileEntity` never escapes this actor.** Every
/// method below either returns a `Sendable` value type (`Profile`, `Int`, `Bool`) or
/// returns nothing; entities are mapped to domain values before the actor boundary
/// is crossed. Returning an entity would hand the caller a live, context-bound
/// reference that could be mutated off-queue.
@ModelActor
actor SwiftDataProfileStore: ProfileStore {

    /// Owned rather than reached for statically, so the entity mapping can
    /// be substituted if the schema ever needs a second interpretation.
    private let mapper = ProfileEntityMapper()


    /// Builds its own stack, so composition instantiates the service in one
    /// line rather than through a separate factory.
    ///
    /// The schema lives here because this is the only type that knows
    /// `ProfileEntity` exists — nothing above the store should have to name it,
    /// which is why the composition root does not import SwiftData.
    ///
    /// - Parameters:
    ///   - isStoredInMemoryOnly: `true` for tests; nothing is written to disk.
    ///   - provider: injectable so a suite can make provisioning itself fail.
    init(
        isStoredInMemoryOnly: Bool = false,
        provider: (any ModelContainerProviding)? = nil
    ) throws(PersistenceError) {
        let provider = provider ?? SwiftDataContainerProvider(
            schema: Schema([ProfileEntity.self]),
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        self.init(modelContainer: try provider.container())
    }

    // MARK: - Reads

    /// Every cached profile, in stable API order.
    ///
    /// The ordering comes from `allSorted()` rather than from
    /// insertion order, which SwiftData does not preserve.
    func profiles() async throws(PersistenceError) -> [Profile] {
        try fetch(allSorted()).map(mapper.toDomain)
    }

    /// The highest page number persisted so far, or `nil` when the store is empty.
    /// The repository derives its paging cursor from this (D-23), so an empty store
    /// starts at page 1 without needing a separately persisted counter that could
    /// fall out of sync with the rows.
    func maxSourcePage() async throws(PersistenceError) -> Int? {
        try fetch(maxSourcePage()).first?.sourcePage
    }

    /// Cheap existence check — a count against the index, with no rows materialised
    /// and nothing mapped to domain.
    func isEmpty() async throws(PersistenceError) -> Bool {
        do {
            return try modelContext.fetchCount(FetchDescriptor<ProfileEntity>()) == 0
        } catch {
            throw PersistenceError.operationFailed
        }
    }

    // MARK: - Writes

    /// Inserts new profiles and refreshes existing ones, in one transaction.
    ///
    /// Matching is by `uuid`, so a page fetched twice updates its rows instead of
    /// duplicating them. Existing rows go through `applyAPIFields`, which leaves the
    /// user's decision untouched (R-1); only genuinely new rows get their status
    /// seeded, via `makeEntity`.
    ///
    /// One `save()` at the end: a page is 10 rows and either all of it lands or none
    /// of it does, which keeps `maxSourcePage` from ever pointing at a half-written
    /// page.
    @discardableResult
    func upsert(_ profiles: [Profile]) async throws(PersistenceError) -> [Profile] {
        guard !profiles.isEmpty else { return [] }

        var persisted: [ProfileEntity] = []
        persisted.reserveCapacity(profiles.count)

        for profile in profiles {
            if let existing = try fetch(byUUID(profile.uuid)).first {
                mapper.applyAPIFields(profile, to: existing)
                persisted.append(existing)
            } else {
                let entity = mapper.makeEntity(from: profile)
                modelContext.insert(entity)
                persisted.append(entity)
            }
        }

        try save()

        // Mapped after saving, so the caller receives stored truth — including
        // any decision this upsert deliberately left alone.
        return persisted.map(mapper.toDomain)
    }

    /// Records a user's Accept/Decline (or a return to pending).
    ///
    /// This is the *only* writer of `statusRaw` and `decidedAt` in the app — the
    /// other half of R-1. A missing row is a real error here: the user acted on
    /// something the store cannot find, and the caller needs to know the tap did not
    /// take effect.
    @discardableResult
    func setStatus(_ status: DecisionStatus, uuid: String) async throws(PersistenceError) -> Profile {
        guard let entity = try fetch(byUUID(uuid)).first else {
            throw PersistenceError.notFound
        }

        entity.statusRaw = status.rawValue
        // The timestamp tracks the decision, so undoing back to `.pending` clears it
        // rather than leaving a stale "decided at" on an undecided row.
        entity.decidedAt = status.isDecided ? .now : nil

        try save()

        // Handed back so the caller can update one element rather than
        // re-reading the whole table.
        return mapper.toDomain(entity)
    }

    /// Caches downloaded portrait bytes against a profile.
    ///
    /// A missing row is deliberately *not* an error, unlike `setStatus`: this runs
    /// from a detached backfill task whose profile may have been replaced since the
    /// download started, and the only consequence is that the image has nowhere to
    /// go. Nothing the user did has been lost, so there is nothing to report.
    @discardableResult
    func saveImage(_ data: Data, uuid: String) async throws(PersistenceError) -> Profile? {
        guard let entity = try fetch(byUUID(uuid)).first else { return nil }

        entity.imageData = data
        try save()
        return mapper.toDomain(entity)
    }

    // MARK: - Context helpers

    /// Fetch, with the store's error vocabulary. Callers get `PersistenceError.operationFailed`
    /// instead of an opaque CoreData error leaking out of the persistence layer.
    private func fetch(_ descriptor: FetchDescriptor<ProfileEntity>) throws(PersistenceError) -> [ProfileEntity] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw PersistenceError.operationFailed
        }
    }

    /// Commit, skipping the round trip when nothing actually changed.
    private func save() throws(PersistenceError) {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            // The context keeps the pending changes; the caller surfaces
            // `PersistenceError.operationFailed.message` ("Couldn't save your change.").
            throw PersistenceError.operationFailed
        }
    }

    // MARK: - Queries

    /// All rows in stable API order: page first, then position within that page.
    ///
    /// The explicit sort is **required**, not cosmetic. SwiftData gives no ordering
    /// guarantee for an unsorted fetch — the underlying store is free to return rows
    /// in whatever order the B-tree walk produces, which changes as rows are updated.
    /// Without this, the match list silently reshuffles between launches (and after
    /// every image backfill write), and a user's position in the list is lost.
    /// `(sourcePage, indexInPage)` reproduces exactly the order the API delivered.
    private func allSorted() -> FetchDescriptor<ProfileEntity> {
        FetchDescriptor<ProfileEntity>(
            sortBy: [
                SortDescriptor(\ProfileEntity.sourcePage, order: .forward),
                SortDescriptor(\ProfileEntity.indexInPage, order: .forward)
            ]
        )
    }

    /// The single row for `uuid`, if it exists.
    ///
    /// `uuid` is `@Attribute(.unique)`, so at most one row can match; the fetch limit
    /// just lets the store stop after the first hit.
    private func byUUID(_ uuid: String) -> FetchDescriptor<ProfileEntity> {
        var descriptor = FetchDescriptor<ProfileEntity>(
            predicate: #Predicate<ProfileEntity> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// The row with the highest `sourcePage`, used to derive the paging cursor
    /// (D-23: `nextPage = maxSourcePage + 1`).
    ///
    /// Sorting descending and taking one row keeps this O(log n) against the index
    /// instead of loading the whole table to compute a maximum.
    private func maxSourcePage() -> FetchDescriptor<ProfileEntity> {
        var descriptor = FetchDescriptor<ProfileEntity>(
            sortBy: [SortDescriptor(\ProfileEntity.sourcePage, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}

