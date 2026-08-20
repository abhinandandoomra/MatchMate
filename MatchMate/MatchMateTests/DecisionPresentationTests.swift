import Foundation
import Testing
@testable import MatchMate

/// The copy a person reads — and a VoiceOver user hears — is now produced by
/// the mappers, so it is assertable. Previously it lived in a view.
struct DecisionBadgeTests {

    @Test("an undecided profile has no badge, so the pill cannot be built for it")
    func pendingHasNoBadge() {
        #expect(DecisionBadge.make(for: .pending) == nil)
    }

    @Test("accepted reads as Accepted, positively toned")
    func accepted() throws {
        let badge = try #require(DecisionBadge.make(for: .accepted))
        #expect(badge.title == "Accepted")
        #expect(badge.tone == .positive)
        #expect(badge.symbolName == "checkmark.circle.fill")
        #expect(badge.accessibilityHint.isEmpty == false)
    }

    @Test("declined reads as Declined, negatively toned")
    func declined() throws {
        let badge = try #require(DecisionBadge.make(for: .declined))
        #expect(badge.title == "Declined")
        #expect(badge.tone == .negative)
    }

    @Test("every state has a row-level description for VoiceOver",
          arguments: DecisionStatus.allCases)
    func descriptions(status: DecisionStatus) {
        #expect(DecisionBadge.description(for: status).isEmpty == false)
    }

    @Test("the row model carries the badge, not raw state to interpret")
    func rowCarriesBadge() {
        #expect(MatchRowMapper.map(.fixture(status: .pending)).decision == nil)
        #expect(MatchRowMapper.map(.fixture(status: .accepted)).decision?.title == "Accepted")
        #expect(MatchRowMapper.map(.fixture(status: .declined)).decision?.tone == .negative)
    }

    @Test("the detail model carries the same badge")
    func detailCarriesBadge() {
        #expect(ProfileDetailMapper.map(.fixture(status: .pending)).decision == nil)
        #expect(ProfileDetailMapper.map(.fixture(status: .accepted)).decision?.title == "Accepted")
    }
}

/// The race the in-flight guard closes: status is read from the repository and
/// written back across an `await`, so two taps in that window would both read
/// the old value.
@MainActor
struct DecisionConcurrencyTests {

    private func make(_ seed: [Profile]) -> (MatchListViewModel, any ProfileRepository, StubProfileStore) {
        let store = StubProfileStore(seed: seed)
        let repo = ProfileRepositoryImpl(store: store, api: StubProfileAPI(), images: StubImageFetcher())
        return (MatchListViewModel(repo: repo, connectivity: StubConnectivity()), repo, store)
    }

    @Test("eight rapid taps on one profile produce exactly one write")
    func rapidTapsCollapse() async throws {
        let (vm, repo, store) = make([.fixture(uuid: "a")])
        try await repo.loadCached()

        async let a: Void = vm.apply(.accept, uuid: "a")
        async let b: Void = vm.apply(.accept, uuid: "a")
        async let c: Void = vm.apply(.accept, uuid: "a")
        async let d: Void = vm.apply(.accept, uuid: "a")
        async let e: Void = vm.apply(.accept, uuid: "a")
        async let f: Void = vm.apply(.accept, uuid: "a")
        async let g: Void = vm.apply(.accept, uuid: "a")
        async let h: Void = vm.apply(.accept, uuid: "a")
        _ = await (a, b, c, d, e, f, g, h)

        #expect(await store.setStatusCount == 1)
        #expect(vm.rows.first?.decision?.title == "Accepted")
    }

    /// The guard promises exactly one write, not which tap wins: `async let`
    /// does not define the order its child tasks start in. Asserting a specific
    /// winner would be asserting scheduler behaviour, and would flake.
    @Test("accept and decline racing still produce exactly one write")
    func conflictingTapsProduceOneWrite() async throws {
        let (vm, repo, store) = make([.fixture(uuid: "a")])
        try await repo.loadCached()

        async let first: Void = vm.apply(.accept, uuid: "a")
        async let second: Void = vm.apply(.decline, uuid: "a")
        _ = await (first, second)

        #expect(await store.setStatusCount == 1)
        // Whichever landed, the profile is decided — never left half-written.
        #expect(vm.rows.first?.decision != nil)
    }

    @Test("a write on one profile never blocks a different profile")
    func guardIsPerProfile() async throws {
        let (vm, repo, store) = make([
            .fixture(uuid: "a"),
            .fixture(uuid: "b", indexInPage: 1),
        ])
        try await repo.loadCached()

        async let a: Void = vm.apply(.accept, uuid: "a")
        async let b: Void = vm.apply(.decline, uuid: "b")
        _ = await (a, b)

        #expect(await store.setStatusCount == 2)
        #expect(vm.rows.first { $0.id == "a" }?.decision?.title == "Accepted")
        #expect(vm.rows.first { $0.id == "b" }?.decision?.title == "Declined")
    }

    @Test("controls are inert only while a write is in flight")
    func busyClearsAfterwards() async throws {
        let (vm, repo, _) = make([.fixture(uuid: "a")])
        try await repo.loadCached()

        #expect(vm.rows.first?.isBusy == false)
        await vm.apply(.accept, uuid: "a")
        #expect(vm.rows.first?.isBusy == false)
    }

    @Test("the detail screen drops rapid taps the same way")
    func detailGuard() async throws {
        let store = StubProfileStore(seed: [.fixture(uuid: "a")])
        let repo = ProfileRepositoryImpl(store: store, api: StubProfileAPI(), images: StubImageFetcher())
        let detail = ProfileDetailViewModel(repo: repo, uuid: "a")
        try await repo.loadCached()

        async let a: Void = detail.apply(.accept)
        async let b: Void = detail.apply(.decline)
        _ = await (a, b)

        #expect(await store.setStatusCount == 1)
        #expect(detail.profile?.decision != nil)
    }

    /// Sequential taps *are* ordered, so the outcome is fully determined there.
    @Test("sequential taps apply in order")
    func sequentialTapsAreOrdered() async throws {
        let (vm, repo, store) = make([.fixture(uuid: "a")])
        try await repo.loadCached()

        await vm.apply(.accept, uuid: "a")
        #expect(vm.rows.first?.decision?.title == "Accepted")

        await vm.apply(.decline, uuid: "a")
        #expect(vm.rows.first?.decision?.title == "Declined")
        #expect(await store.setStatusCount == 2)
    }
}
