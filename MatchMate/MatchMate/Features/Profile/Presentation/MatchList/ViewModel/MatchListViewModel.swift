import Foundation
import Observation

/// Owns list state *and* navigation. The view is a pure function of this object.
@MainActor
@Observable
final class MatchListViewModel {

    /// How many rows from the end trigger the next page. A presentation
    /// concern, so it lives with the screen that applies it.
    static let prefetchDistance = 3

    // MARK: - Navigation

    /// The ViewModel owns the stack, so a decision made in detail can pop, and
    /// a deep link can push, without the view holding any state of its own.
    var path: [Route] = []

    // MARK: - State

    private(set) var isLoadingPage = false
    private(set) var pageError: ProfileError?

    /// The error type itself never reaches a view — only this resolved copy,
    /// carried inside `state`.
    private var pageErrorMessage: String? { pageError.map(ProfileErrorText.message(for:)) }
    /// True until the first `onAppear` pass finishes, so the list can show a
    /// full-screen spinner instead of an empty-state flash.
    private(set) var isFirstLoad = true
    private(set) var isOnline = true

    private let repo: any ProfileRepository

    /// Profiles with a decision write in flight. Per-profile rather than a
    /// single flag, so deciding one match never blocks another.
    private var inFlight: Set<String> = []
    private let connectivity: ConnectivityMonitoring
    private var connectivityTask: Task<Void, Never>?

    init(repo: any ProfileRepository, connectivity: ConnectivityMonitoring) {
        self.repo = repo
        self.connectivity = connectivity
    }

    // MARK: - Projection

    /// MUST be COMPUTED, never stored.
    ///
    /// `repo.profiles` is the single source of truth. Storing a copy here would
    /// mean this property is only re-read when *it* changes — Observation would
    /// stop seeing the repository's mutation, and the list would silently stop
    /// updating after an accept/decline or a new page. Reading through on every
    /// access is what registers the dependency on `repo.profiles`.
    var rows: [MatchRowUIModel] {
        repo.profiles.map { MatchRowMapper.map($0, isBusy: inFlight.contains($0.uuid)) }
    }

    private var hasContent: Bool { !repo.profiles.isEmpty }

    /// The single thing the view switches on.
    ///
    /// A blocking error is only ever appropriate when there is nothing to show;
    /// with anything cached we keep it on screen and degrade to a footer retry
    /// plus the offline banner. Expressing that as one enum rather than four
    /// booleans is what stops the view from having to re-derive the rule.
    var state: MatchListState {
        let rows = self.rows

        guard hasContent else {
            if isLoadingPage || isFirstLoad { return .loading }
            if let pageErrorMessage { return .failed(message: pageErrorMessage) }
            return .empty
        }

        if isLoadingPage { return .loaded(rows: rows, footer: .loadingMore) }
        if let pageErrorMessage { return .loaded(rows: rows, footer: .failed(message: pageErrorMessage)) }
        return .loaded(rows: rows, footer: .idle)
    }

    /// An overlay rather than a state: it sits *over* loaded content, so it is
    /// orthogonal to what the feed itself is doing.
    var showsOfflineBanner: Bool { !isOnline && hasContent }

    // MARK: - Lifecycle

    func onAppear() async {
        startObservingConnectivity()
        isOnline = await connectivity.isOnline

        // FR-11 — whatever is on disk goes on screen before any network work.
        try? await repo.loadCached()
        if repo.profiles.isEmpty {
            await loadNextPage()
        }
        isFirstLoad = false
    }

    // MARK: - Paging

    func rowAppeared(at index: Int) async {
        guard index >= repo.profiles.count - Self.prefetchDistance else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        // In-flight guard: a fast scroll fires `rowAppeared` for several rows in
        // the same runloop turn, and every one of them lands here. Collapsing
        // them into a single request is what keeps paging from stampeding.
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            try await repo.loadNextPage()
            pageError = nil
        } catch {
            // A scroll-away or dismissal cancels the request; that is not a
            // failure the user should see a retry prompt for.
            if error != .network(.cancelled) { pageError = error }
        }
    }

    func retry() async {
        pageError = nil
        await loadNextPage()
    }

    // MARK: - Decisions

    /// Rapid or double taps are dropped rather than queued.
    ///
    /// The decision is read from the repository and written back across an
    /// `await`, so two taps landing in that window would both read the *old*
    /// status and race — accept-then-decline could resolve either way. This
    /// ViewModel is `@MainActor`, so a single in-flight set is enough to make
    /// the second tap a no-op, and `isBusy` makes the control inert meanwhile.
    /// Translates a view's intent into domain state. The view never names a
    /// `DecisionStatus`; this is the only place the two vocabularies meet.
    func apply(_ intent: DecisionIntent, uuid: String) async {
        guard !inFlight.contains(uuid) else { return }
        guard repo.profile(uuid: uuid) != nil else { return }

        inFlight.insert(uuid)
        defer { inFlight.remove(uuid) }

        try? await repo.setStatus(Self.status(for: intent), uuid: uuid)
    }

    static func status(for intent: DecisionIntent) -> DecisionStatus {
        switch intent {
        case .accept: .accepted
        case .decline: .declined
        case .undo: .pending
        }
    }

    // MARK: - Navigation intent

    func openDetail(uuid: String) {
        path.append(.detail(uuid: uuid))
    }

    // MARK: - Connectivity

    private func startObservingConnectivity() {
        guard connectivityTask == nil else { return }
        let stream = connectivity.stream()
        connectivityTask = Task { [weak self] in
            for await online in stream {
                guard let self else { return }
                self.isOnline = online
            }
        }
    }
}
