import Foundation
@testable import MatchMate

/// In-memory ProfileStore. Lets every ViewModel and repository test run with no
/// SwiftData and no ModelContainer — which is the whole point of keeping the
/// store protocol keyed by `login.uuid` rather than `PersistentIdentifier`.
actor StubProfileStore: ProfileStore {
    private var storage: [String: Profile] = [:]
    private(set) var upsertCount = 0
    private(set) var setStatusCount = 0
    private var errorOnUpsert: PersistenceError?
    private var errorOnRead: PersistenceError?

    init(seed: [Profile] = []) {
        for profile in seed { storage[profile.uuid] = profile }
    }

    func failUpsert(with error: PersistenceError?) { errorOnUpsert = error }
    func failReads(with error: PersistenceError?) { errorOnRead = error }

    func profiles() async throws(PersistenceError) -> [Profile] {
        if let errorOnRead { throw errorOnRead }
        return storage.values.sorted {
            ($0.sourcePage, $0.indexInPage) < ($1.sourcePage, $1.indexInPage)
        }
    }

    @discardableResult
    func upsert(_ profiles: [Profile]) async throws(PersistenceError) -> [Profile] {
        if let errorOnUpsert { throw errorOnUpsert }
        upsertCount += 1
        var persisted: [Profile] = []
        for incoming in profiles {
            if var existing = storage[incoming.uuid] {
                // R-1 mirrored: preserve the user-owned decision on re-upsert.
                let status = existing.status
                let decidedAt = existing.decidedAt
                existing = incoming
                existing.status = status
                existing.decidedAt = decidedAt
                storage[incoming.uuid] = existing
                persisted.append(existing)
            } else {
                storage[incoming.uuid] = incoming
                persisted.append(incoming)
            }
        }
        return persisted
    }

    @discardableResult
    func setStatus(_ status: DecisionStatus, uuid: String) async throws(PersistenceError) -> Profile {
        guard var profile = storage[uuid] else { throw PersistenceError.notFound }
        setStatusCount += 1
        profile.status = status
        profile.decidedAt = status.isDecided ? Date(timeIntervalSince1970: 0) : nil
        storage[uuid] = profile
        return profile
    }

    @discardableResult
    func saveImage(_ data: Data, uuid: String) async throws(PersistenceError) -> Profile? {
        guard var profile = storage[uuid] else { return nil }
        profile.imageData = data
        storage[uuid] = profile
        return profile
    }

    func maxSourcePage() async throws(PersistenceError) -> Int? {
        storage.values.map(\.sourcePage).max()
    }

    func isEmpty() async throws(PersistenceError) -> Bool { storage.isEmpty }
}
