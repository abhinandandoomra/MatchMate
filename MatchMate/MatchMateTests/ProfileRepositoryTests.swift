import Foundation
import Testing
@testable import MatchMate

@MainActor
struct ProfileRepositoryTests {

    private func makeRepo(
        seed: [Profile] = [],
        api: StubProfileAPI = StubProfileAPI(),
        images: StubImageFetcher = StubImageFetcher()
    ) -> (any ProfileRepository, StubProfileStore, StubProfileAPI) {
        let store = StubProfileStore(seed: seed)
        return (ProfileRepositoryImpl(store: store, api: api, images: images), store, api)
    }

    @Test("loadCached shows what is stored and never calls the network — FR-11/FR-13")
    func loadCachedIsOffline() async throws {
        let (repo, _, api) = makeRepo(seed: [.fixture(uuid: "a"), .fixture(uuid: "b", indexInPage: 1)])
        try await repo.loadCached()

        #expect(repo.profiles.count == 2)
        #expect(await api.pages().isEmpty)
    }

    @Test("the cursor is derived from stored rows and survives a cold start — D-23")
    func cursorFromStoredRows() async throws {
        let (repo, _, _) = makeRepo(seed: [
            .fixture(uuid: "a", sourcePage: 1),
            .fixture(uuid: "b", sourcePage: 4),
        ])
        try await repo.loadCached()
        #expect(repo.nextPage == 5)
    }

    @Test("an empty store starts at page 1")
    func emptyStartsAtOne() async throws {
        let (repo, _, _) = makeRepo()
        try await repo.loadCached()
        #expect(repo.nextPage == 1)
    }

    @Test("loadNextPage persists a page and advances the cursor")
    func pagingAdvances() async throws {
        let (repo, _, api) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()

        #expect(repo.profiles.count == ProfileAPIConfig.test.pageSize)
        #expect(repo.nextPage == 2)
        #expect(await api.pages() == [1])

        try await repo.loadNextPage()
        #expect(repo.profiles.count == ProfileAPIConfig.test.pageSize * 2)
        #expect(repo.nextPage == 3)
        #expect(await api.pages() == [1, 2])
    }

    /// FR-16 — the failure case that must not corrupt paging.
    @Test("a failed page writes nothing and leaves the cursor untouched")
    func failureDoesNotAdvanceCursor() async throws {
        let (repo, _, api) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()
        #expect(repo.nextPage == 2)

        await api.fail(with: .timeout)
        await #expect(throws: ProfileError.network(.timeout)) { try await repo.loadNextPage() }

        #expect(repo.nextPage == 2)                       // unchanged
        #expect(repo.profiles.count == ProfileAPIConfig.test.pageSize)   // nothing partial persisted

        // Retry requests the same page, not the next one.
        await api.fail(with: nil)
        try await repo.loadNextPage()
        #expect(await api.pages() == [1, 2, 2])
        #expect(repo.nextPage == 3)
    }

    @Test("setStatus writes through and re-projects")
    func setStatusReprojects() async throws {
        let (repo, _, _) = makeRepo(seed: [.fixture(uuid: "a")])
        try await repo.loadCached()
        #expect(repo.profiles[0].status == .pending)

        try await repo.setStatus(.accepted, uuid: "a")
        #expect(repo.profiles[0].status == .accepted)
    }

    @Test("re-fetching a page cannot clobber a decision — R-1 end to end")
    func refetchPreservesDecision() async throws {
        let (repo, _, api) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()

        let uuid = repo.profiles[0].uuid
        try await repo.setStatus(.declined, uuid: uuid)
        #expect(repo.profile(uuid: uuid)?.status == .declined)

        // Force the same page through the sync path again.
        await api.fail(with: nil)
        try await repo.loadNextPage()

        #expect(repo.profile(uuid: uuid)?.status == .declined)
    }

    @Test("images are fetched for a new page and persisted")
    func imageBackfill() async throws {
        let images = StubImageFetcher(result: .success(Data([0xFF, 0xD8, 0xFF])))
        let (repo, _, _) = makeRepo(images: images)
        try await repo.loadCached()
        try await repo.loadNextPage()

        #expect(images.requested.count == ProfileAPIConfig.test.pageSize)
        #expect(repo.profiles.allSatisfy { $0.imageData != nil })
    }

    @Test("a failed image download is not fatal — the page still loads")
    func imageFailureIsNotFatal() async throws {
        let images = StubImageFetcher(result: .failure(.timeout))
        let (repo, _, _) = makeRepo(images: images)
        try await repo.loadCached()
        try await repo.loadNextPage()

        #expect(repo.profiles.count == ProfileAPIConfig.test.pageSize)
        #expect(repo.profiles.allSatisfy { $0.imageData == nil })
    }

    @Test("cached profiles missing bytes are retried on launch — F-10")
    func imageBackfillOnWarmLaunch() async throws {
        let images = StubImageFetcher(result: .success(Data([1, 2])))
        let (repo, _, _) = makeRepo(seed: [.fixture(uuid: "a", imageData: nil)], images: images)

        try await repo.loadCached()

        #expect(images.requested.count == 1)
        #expect(repo.profiles[0].imageData == Data([1, 2]))
    }
}

/// Translation is the repository's job now, so its output is where mapping is
/// verified end to end.
@MainActor
struct ProfileRepositoryMappingTests {

    private func makeRepo() -> (any ProfileRepository, StubProfileAPI) {
        let api = StubProfileAPI()
        return (ProfileRepositoryImpl(store: StubProfileStore(), api: api, images: StubImageFetcher()), api)
    }

    @Test("the requested page is stamped onto every profile it persists")
    func stampsOrdering() async throws {
        let (repo, _) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()

        #expect(repo.profiles.allSatisfy { $0.sourcePage == 1 })
        #expect(repo.profiles.map(\.indexInPage) == Array(0..<ProfileAPIConfig.test.pageSize))
    }

    @Test("a second page is stamped with its own page number")
    func stampsSecondPage() async throws {
        let (repo, _) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()
        try await repo.loadNextPage()

        let pages = Set(repo.profiles.map(\.sourcePage))
        #expect(pages == [1, 2])
    }

    @Test("a freshly mapped profile carries no user state — R-1 at the wire boundary")
    func noUserState() async throws {
        let (repo, _) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()

        #expect(repo.profiles.allSatisfy { $0.status == .pending })
        #expect(repo.profiles.allSatisfy { $0.decidedAt == nil })
    }

    @Test("wire fields reach the domain intact")
    func mapsFields() async throws {
        let (repo, _) = makeRepo()
        try await repo.loadCached()
        try await repo.loadNextPage()

        let first = try #require(repo.profiles.first)
        #expect(first.uuid == "uuid-1-0")
        #expect(first.fullName == "First1-0 Last1-0")
        #expect(first.country == "Turkey")
        #expect(first.nationalityCode == "TR")
    }
}
