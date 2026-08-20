import SwiftUI

/// Owns the list ViewModel for the lifetime of the screen.
///
/// The ViewModel is built in `init` and held in `@State` rather than created in
/// `body`: a body re-evaluation would otherwise construct a fresh one and
/// silently discard `isLoadingPage`, `pageError` and the navigation path.
///
/// The repository is *handed in* rather than built here — that same instance is
/// closed over for the detail screen, which is the whole of the list/detail
/// consistency mechanism.
@MainActor
struct MatchListScreen: View {
    private let repository: any ProfileRepository
    @State private var viewModel: MatchListViewModel

    init(repository: any ProfileRepository, connectivity: any ConnectivityMonitoring = NetworkMonitor()) {
        self.repository = repository
        _viewModel = State(initialValue: MatchListViewModel(repo: repository, connectivity: connectivity))
    }

    var body: some View {
        MatchListView(
            viewModel: viewModel,
            makeDetailViewModel: { ProfileDetailViewModel(repo: repository, uuid: $0) }
        )
    }
}
