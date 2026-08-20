import Foundation
import Testing
@testable import MatchMate

@MainActor
struct ViewModelTests {

    private func makeList(
        seed: [Profile] = [],
        api: StubProfileAPI = StubProfileAPI(),
        online: Bool = true
    ) -> (MatchListViewModel, ProfileRepository, StubProfileAPI) {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(seed: seed), api: api, images: StubImageFetcher())
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity(online: online))
        return (vm, repo, api)
    }

    // MARK: - Launch

    @Test("an empty database triggers the first page — FR-12")
    func emptyDatabaseFetches() async {
        let (vm, _, api) = makeList()
        await vm.onAppear()
        #expect(await api.pages() == [1])
        #expect(vm.rows.count == ProfileAPIConfig.test.pageSize)
    }

    @Test("a warm launch with cached rows makes no network call at all — FR-13")
    func warmLaunchIsSilent() async {
        let (vm, _, api) = makeList(seed: [.fixture(uuid: "a")])
        await vm.onAppear()
        #expect(await api.pages().isEmpty)
        #expect(vm.rows.count == 1)
    }

    // MARK: - Pagination

    @Test("paging only triggers within the prefetch window — TD-05")
    func prefetchThreshold() async {
        let (vm, _, api) = makeList()
        await vm.onAppear()                       // 10 rows, page 1 fetched
        #expect(await api.pages() == [1])

        await vm.rowAppeared(at: 0)               // far from the end
        #expect(await api.pages() == [1])

        await vm.rowAppeared(at: ProfileAPIConfig.test.pageSize - MatchListViewModel.prefetchDistance)
        #expect(await api.pages() == [1, 2])
    }

    /// O-3 — fast scrolling fires onAppear many times; only one request may go out.
    @Test("concurrent scroll triggers collapse into a single request")
    func inFlightGuard() async {
        let (vm, _, api) = makeList()
        await vm.onAppear()

        // Eight overlapping triggers, as fast scrolling would produce.
        async let a: Void = vm.loadNextPage()
        async let b: Void = vm.loadNextPage()
        async let c: Void = vm.loadNextPage()
        async let d: Void = vm.loadNextPage()
        async let e: Void = vm.loadNextPage()
        async let f: Void = vm.loadNextPage()
        async let g: Void = vm.loadNextPage()
        async let h: Void = vm.loadNextPage()
        _ = await (a, b, c, d, e, f, g, h)

        #expect(await api.pages() == [1, 2])
    }

    @Test("a page failure surfaces an error but keeps the list intact — FR-16")
    func pageFailureKeepsContent() async {
        let (vm, _, api) = makeList()
        await vm.onAppear()

        await api.fail(with: .timeout)
        await vm.loadNextPage()

        #expect(vm.pageError == .network(.timeout))
        #expect(vm.rows.count == ProfileAPIConfig.test.pageSize)
        // Cached content stays on screen; the failure degrades to the footer.
        #expect(vm.state == .loaded(rows: vm.rows, footer: .failed(
            message: ProfileErrorText.message(for: NetworkError.timeout))))
    }

    @Test("retry clears the error and re-requests the same page")
    func retryRequestsSamePage() async {
        let (vm, _, api) = makeList()
        await vm.onAppear()
        await api.fail(with: .timeout)
        await vm.loadNextPage()

        await api.fail(with: nil)
        await vm.retry()

        #expect(vm.pageError == nil)
        #expect(await api.pages() == [1, 2, 2])
    }

    @Test("a first-load failure with nothing cached is full-screen")
    func firstLoadFailureIsFullScreen() async {
        let (vm, _, _) = makeList(api: StubProfileAPI(error: .offline))
        await vm.onAppear()
        #expect(vm.rows.isEmpty)
        #expect(vm.state == .failed(
            message: ProfileErrorText.message(for: NetworkError.offline)))
    }

    // MARK: - Decisions

    @Test("accepting updates the row — FR-07/FR-08")
    func acceptUpdatesRow() async {
        let (vm, _, _) = makeList(seed: [.fixture(uuid: "a")])
        await vm.onAppear()

        await vm.apply(.accept, uuid: "a")
        #expect(vm.rows.first?.decision?.title == "Accepted")
    }

    @Test("tapping the active status undoes it — D-26")
    func undo() async {
        let (vm, _, _) = makeList(seed: [.fixture(uuid: "a")])
        await vm.onAppear()

        await vm.apply(.accept, uuid: "a")
        await vm.apply(.undo, uuid: "a")
        #expect(vm.rows.first?.decision == nil)
    }

    @Test("a decision can be switched directly")
    func switchDecision() async {
        let (vm, _, _) = makeList(seed: [.fixture(uuid: "a")])
        await vm.onAppear()

        await vm.apply(.accept, uuid: "a")
        await vm.apply(.decline, uuid: "a")
        #expect(vm.rows.first?.decision?.title == "Declined")
    }

    @Test("navigation is observable state — TD-06")
    func navigation() async {
        let (vm, _, _) = makeList(seed: [.fixture(uuid: "a")])
        await vm.onAppear()
        vm.openDetail(uuid: "a")
        #expect(vm.path == [.detail(uuid: "a")])
    }

    @Test("the offline banner only shows when there is cached content to show")
    func offlineBanner() async {
        let (vm, _, _) = makeList(seed: [.fixture(uuid: "a")], online: false)
        await vm.onAppear()
        #expect(vm.showsOfflineBanner)
    }

    // MARK: - FR-20, the requirement the architecture exists for

    @Test("a decision made on detail is already visible to the list — FR-19/FR-20")
    func detailChangeIsVisibleToListImmediately() async throws {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(seed: [.fixture(uuid: "a")]),
            api: StubProfileAPI(), images: StubImageFetcher())
        let listVM = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        let detailVM = ProfileDetailViewModel(repo: repo, uuid: "a")

        try await repo.loadCached()
        #expect(listVM.rows.first?.decision == nil)

        await detailVM.apply(.accept)

        #expect(detailVM.profile?.decision?.title == "Accepted")      // FR-19 — detail updates now
        #expect(listVM.rows.first?.decision?.title == "Accepted")     // FR-20 — no navigation involved
    }

    @Test("the reverse also holds: a list decision is visible on detail")
    func listChangeIsVisibleToDetail() async throws {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(seed: [.fixture(uuid: "a")]),
            api: StubProfileAPI(), images: StubImageFetcher())
        let listVM = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        let detailVM = ProfileDetailViewModel(repo: repo, uuid: "a")

        try await repo.loadCached()
        await listVM.apply(.decline, uuid: "a")

        #expect(detailVM.profile?.decision?.title == "Declined")
    }

    @Test("detail reports a missing profile rather than crashing")
    func missingProfile() async throws {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(), api: StubProfileAPI(), images: StubImageFetcher())
        let detailVM = ProfileDetailViewModel(repo: repo, uuid: "ghost")
        try await repo.loadCached()
        #expect(detailVM.isMissing)
    }
}

/// The state enum replaced four booleans whose combinations included states the
/// ViewModel could never actually produce.
@MainActor
struct MatchListStateTests {

    private func make(seed: [Profile] = [], api: StubProfileAPI = StubProfileAPI())
    -> (MatchListViewModel, any ProfileRepository) {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(seed: seed), api: api, images: StubImageFetcher())
        return (MatchListViewModel(repo: repo, connectivity: StubConnectivity()), repo)
    }

    @Test("before anything loads, the list is loading — not empty")
    func startsLoading() {
        let (vm, _) = make()
        #expect(vm.state == .loading)
    }

    @Test("a successful load reports rows with an idle footer")
    func loadedIdle() async {
        let (vm, _) = make()
        await vm.onAppear()

        guard case .loaded(let rows, let footer) = vm.state else {
            Issue.record("expected .loaded, got \(vm.state)"); return
        }
        #expect(rows.count == ProfileAPIConfig.test.pageSize)
        #expect(footer == .idle)
    }

    @Test("a first-load failure with nothing cached is a full-screen failure")
    func failedWhenNothingCached() async {
        let (vm, _) = make(api: StubProfileAPI(error: .offline))
        await vm.onAppear()
        #expect(vm.state == .failed(message: ProfileErrorText.message(for: NetworkError.offline)))
    }

    @Test("the same failure with cached rows degrades to a footer, not a wall")
    func failureDegradesWithContent() async {
        let api = StubProfileAPI()
        let (vm, _) = make(api: api)
        await vm.onAppear()

        await api.fail(with: .timeout)
        await vm.loadNextPage()

        guard case .loaded(_, let footer) = vm.state else {
            Issue.record("expected .loaded, got \(vm.state)"); return
        }
        #expect(footer == .failed(message: ProfileErrorText.message(for: NetworkError.timeout)))
    }

    @Test("an empty result set is empty, not a failure")
    func emptyIsNotFailure() async {
        let api = StubProfileAPI(pageSize: 0)
        let (vm, _) = make(api: api)
        await vm.onAppear()
        #expect(vm.state == .empty)
    }
}

/// Found on a physical device with no network route and an empty store: the
/// full-screen failure promised "Showing saved matches" when there were none.
@MainActor
struct OfflineCopyTests {

    @Test("a total offline failure does not promise cached matches")
    func offlineWithNothingCached() async {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(), api: StubProfileAPI(error: .offline),
            images: StubImageFetcher())
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity(online: false))

        await vm.onAppear()

        #expect(vm.state == .failed(message: ProfileErrorText.offlineWithNothingCached))
        #expect(ProfileErrorText.offlineWithNothingCached.contains("saved matches") == false)
    }

    @Test("the banner over cached content still promises them, because they exist")
    func offlineWithCache() async throws {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(seed: [.fixture(uuid: "a")]),
            api: StubProfileAPI(error: .offline), images: StubImageFetcher())
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity(online: false))

        await vm.onAppear()

        #expect(vm.showsOfflineBanner)
        #expect(ProfileErrorText.offlineWithCache.contains("saved matches"))
    }
}
