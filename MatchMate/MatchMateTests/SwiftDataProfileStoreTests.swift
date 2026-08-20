import Foundation
import Testing
import SwiftData
@testable import MatchMate

/// The only suite that touches SwiftData, and it uses an in-memory container so
/// nothing reaches disk (NFR-06).
struct SwiftDataProfileStoreTests {

    /// Goes through the same entry point production uses, so the suite proves
    /// the real provisioning path rather than a parallel one that could drift.
    private func makeStore() throws -> any ProfileStore {
        try SwiftDataProfileStore(isStoredInMemoryOnly: true)
    }

    @Test("a fresh store is empty and has no cursor")
    func emptyStore() async throws {
        let store = try makeStore()
        #expect(try await store.isEmpty())
        #expect(try await store.maxSourcePage() == nil)
        #expect(try await store.profiles().isEmpty)
    }

    @Test("upsert inserts, then updates rather than duplicating")
    func upsertIsIdempotent() async throws {
        let store = try makeStore()
        try await store.upsert([.fixture(uuid: "a", firstName: "One")])
        try await store.upsert([.fixture(uuid: "a", firstName: "Two")])

        let profiles = try await store.profiles()
        #expect(profiles.count == 1)
        #expect(profiles[0].firstName == "Two")
    }

    @Test("R-1 holds through the store: re-upsert preserves a decision")
    func upsertPreservesDecision() async throws {
        let store = try makeStore()
        try await store.upsert([.fixture(uuid: "a")])
        try await store.setStatus(.accepted, uuid: "a")

        try await store.upsert([.fixture(uuid: "a", firstName: "Refreshed")])

        let profile = try await store.profiles()[0]
        #expect(profile.status == .accepted)
        #expect(profile.firstName == "Refreshed")
    }

    @Test("rows come back in (sourcePage, indexInPage) order regardless of insert order")
    func stableOrdering() async throws {
        let store = try makeStore()
        try await store.upsert([
            .fixture(uuid: "p2i1", sourcePage: 2, indexInPage: 1),
            .fixture(uuid: "p1i1", sourcePage: 1, indexInPage: 1),
            .fixture(uuid: "p2i0", sourcePage: 2, indexInPage: 0),
            .fixture(uuid: "p1i0", sourcePage: 1, indexInPage: 0),
        ])
        #expect(try await store.profiles().map(\.uuid) == ["p1i0", "p1i1", "p2i0", "p2i1"])
    }

    @Test("the cursor is the highest persisted page")
    func cursor() async throws {
        let store = try makeStore()
        try await store.upsert([
            .fixture(uuid: "a", sourcePage: 1),
            .fixture(uuid: "b", sourcePage: 3),
            .fixture(uuid: "c", sourcePage: 2),
        ])
        #expect(try await store.maxSourcePage() == 3)
    }

    @Test("setStatus stamps decidedAt, and clears it on undo")
    func statusTimestamps() async throws {
        let store = try makeStore()
        try await store.upsert([.fixture(uuid: "a")])

        try await store.setStatus(.accepted, uuid: "a")
        #expect(try await store.profiles()[0].decidedAt != nil)

        try await store.setStatus(.pending, uuid: "a")
        let reverted = try await store.profiles()[0]
        #expect(reverted.status == .pending)
        #expect(reverted.decidedAt == nil)
    }

    @Test("setStatus on an unknown profile reports notFound")
    func statusNotFound() async throws {
        let store = try makeStore()
        await #expect(throws: PersistenceError.notFound) {
            try await store.setStatus(.accepted, uuid: "ghost")
        }
    }

    @Test("saveImage persists bytes against the right row")
    func saveImage() async throws {
        let store = try makeStore()
        try await store.upsert([.fixture(uuid: "a"), .fixture(uuid: "b", indexInPage: 1)])
        try await store.saveImage(Data([9, 9]), uuid: "a")

        let profiles = try await store.profiles()
        #expect(profiles.first { $0.uuid == "a" }?.imageData == Data([9, 9]))
        #expect(profiles.first { $0.uuid == "b" }?.imageData == nil)
    }

    @Test("saveImage for a missing row is a no-op, not a failure")
    func saveImageMissingRow() async throws {
        let store = try makeStore()
        try await store.saveImage(Data([1]), uuid: "ghost")
        #expect(try await store.isEmpty())
    }
}
