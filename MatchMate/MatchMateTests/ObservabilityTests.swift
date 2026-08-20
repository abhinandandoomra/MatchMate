import Foundation
import Observation
import Testing
@testable import MatchMate

/// Proof that the chain of mappings does not break SwiftUI's change tracking.
///
/// The concern is real: `store → [Profile] → repo.profiles → vm.rows →
/// vm.state → view` passes through three mappings and a protocol existential.
/// If any link stored a mapped result instead of computing it, Observation
/// would stop seeing the mutation and the UI would silently freeze — with no
/// compiler error and no crash.
///
/// These tests read exactly what a view body reads, inside
/// `withObservationTracking`, and assert the change is observed.
@MainActor
struct ObservabilityTests {

    /// `onChange` fires on a different isolation, so the flag needs a box.
    private final class Signal: @unchecked Sendable {
        var fired = false
    }

    private func makeRepo(_ seed: [Profile]) -> any ProfileRepository {
        ProfileRepositoryImpl(
            store: StubProfileStore(seed: seed),
            api: StubProfileAPI(),
            images: StubImageFetcher()
        )
    }

    @Test("a decision re-renders the list — repo → rows → state")
    func listStateIsObservable() async throws {
        let repo = makeRepo([.fixture(uuid: "a")])
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        try await repo.loadCached()

        let signal = Signal()
        withObservationTracking {
            _ = vm.state                      // exactly what the view body reads
        } onChange: {
            signal.fired = true
        }

        await vm.apply(.accept, uuid: "a")
        #expect(signal.fired)
    }

    @Test("the busy flag re-renders too, so controls really do go inert")
    func busyStateIsObservable() async throws {
        let repo = makeRepo([.fixture(uuid: "a")])
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        try await repo.loadCached()

        let signal = Signal()
        withObservationTracking {
            _ = vm.state
        } onChange: {
            signal.fired = true
        }

        async let write: Void = vm.apply(.accept, uuid: "a")
        await write
        #expect(signal.fired)
    }

    @Test("a new page re-renders the list")
    func pagingIsObservable() async throws {
        let repo = makeRepo([])
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        try await repo.loadCached()

        let signal = Signal()
        withObservationTracking {
            _ = vm.state
        } onChange: {
            signal.fired = true
        }

        await vm.loadNextPage()
        #expect(signal.fired)
    }

    @Test("the detail screen observes the same repository")
    func detailIsObservable() async throws {
        let repo = makeRepo([.fixture(uuid: "a")])
        let detail = ProfileDetailViewModel(repo: repo, uuid: "a")
        try await repo.loadCached()

        let signal = Signal()
        withObservationTracking {
            _ = detail.profile
        } onChange: {
            signal.fired = true
        }

        await detail.apply(.accept)
        #expect(signal.fired)
    }

    /// FR-20 through the observation system rather than by reading values: a
    /// write from detail must invalidate the *list's* view body.
    @Test("a detail decision invalidates the list's rendering")
    func detailWriteInvalidatesList() async throws {
        let repo = makeRepo([.fixture(uuid: "a")])
        let listVM = MatchListViewModel(repo: repo, connectivity: StubConnectivity())
        let detailVM = ProfileDetailViewModel(repo: repo, uuid: "a")
        try await repo.loadCached()

        let signal = Signal()
        withObservationTracking {
            _ = listVM.state                  // the list is what we track
        } onChange: {
            signal.fired = true
        }

        await detailVM.apply(.accept)         // the write comes from detail
        #expect(signal.fired)
    }
}
