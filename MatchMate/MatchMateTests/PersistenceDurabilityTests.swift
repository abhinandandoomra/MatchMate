import Foundation
import SwiftData
import Testing
@testable import MatchMate

/// Guards the one acceptance criterion no in-memory test can cover: *kill the
/// app, reopen, the statuses are still there.*
///
/// This matters because the failure mode is invisible in a running session. A
/// `@ModelActor`'s context has `autosaveEnabled == false`, so a mutation without
/// `save()` is still returned by every subsequent read from that context — the
/// UI looks entirely correct — and is simply never written to disk. Only
/// reopening the store from a fresh container exposes it.
@Suite(.serialized)
struct PersistenceDurabilityTests {

    /// Each test gets its own file, removed afterwards, so nothing leaks between runs.
    private func withTemporaryStore(
        _ body: (URL) async throws -> Void
    ) async throws {
        let url = URL.temporaryDirectory.appending(path: "matchmate-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
            }
        }
        try await body(url)
    }

    private func store(at url: URL) throws -> SwiftDataProfileStore {
        let schema = Schema([ProfileEntity.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        return SwiftDataProfileStore(modelContainer: container)
    }

    @Test("a decision survives the store being reopened")
    func decisionSurvivesReopen() async throws {
        try await withTemporaryStore { url in
            do {
                let first = try store(at: url)
                try await first.upsert([.fixture(uuid: "a")])
                try await first.setStatus(.accepted, uuid: "a")
            }

            let reopened = try store(at: url)
            let profile = try #require(try await reopened.profiles().first)
            #expect(profile.status == .accepted)
            #expect(profile.decidedAt != nil)
        }
    }

    @Test("an undo survives too, clearing the timestamp")
    func undoSurvivesReopen() async throws {
        try await withTemporaryStore { url in
            do {
                let first = try store(at: url)
                try await first.upsert([.fixture(uuid: "a")])
                try await first.setStatus(.declined, uuid: "a")
                try await first.setStatus(.pending, uuid: "a")
            }

            let reopened = try store(at: url)
            let profile = try #require(try await reopened.profiles().first)
            #expect(profile.status == .pending)
            #expect(profile.decidedAt == nil)
        }
    }

    @Test("fetched pages and portrait bytes survive")
    func pagesAndImagesSurviveReopen() async throws {
        try await withTemporaryStore { url in
            do {
                let first = try store(at: url)
                try await first.upsert((0..<10).map {
                    .fixture(uuid: "u-\($0)", sourcePage: 1, indexInPage: $0)
                })
                try await first.saveImage(Data([0xFF, 0xD8]), uuid: "u-3")
            }

            let reopened = try store(at: url)
            let profiles = try await reopened.profiles()
            #expect(profiles.count == 10)
            #expect(try await reopened.maxSourcePage() == 1)
            #expect(profiles.first { $0.uuid == "u-3" }?.imageData == Data([0xFF, 0xD8]))
        }
    }

    @Test("ordering survives, so the list cannot reshuffle between launches")
    func orderSurvivesReopen() async throws {
        try await withTemporaryStore { url in
            do {
                let first = try store(at: url)
                try await first.upsert([
                    .fixture(uuid: "p2i1", sourcePage: 2, indexInPage: 1),
                    .fixture(uuid: "p1i0", sourcePage: 1, indexInPage: 0),
                    .fixture(uuid: "p2i0", sourcePage: 2, indexInPage: 0),
                    .fixture(uuid: "p1i1", sourcePage: 1, indexInPage: 1),
                ])
            }

            let reopened = try store(at: url)
            #expect(try await reopened.profiles().map(\.uuid) == ["p1i0", "p1i1", "p2i0", "p2i1"])
        }
    }
}
