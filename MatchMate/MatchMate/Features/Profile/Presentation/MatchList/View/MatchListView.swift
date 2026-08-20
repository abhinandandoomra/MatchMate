import SwiftUI

/// The match feed. Renders exactly one thing: whatever `viewModel.state` says.
///
/// The view holds no state of its own and derives no rules — it does not ask
/// "is there content *and* an error *and* not loading". That decision was made
/// once, in the ViewModel, and arrives here as a single case.
@MainActor
struct MatchListView: View {
    @Environment(\.profileStyle) private var style

    /// Owned by `MatchListScreen`, not by this view — see its documentation.
    @Bindable var viewModel: MatchListViewModel

    /// Injected so the detail screen is handed the *same* `ProfileRepository`
    /// the list uses.
    let makeDetailViewModel: @MainActor (String) -> ProfileDetailViewModel

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(style.screenBackground)
                .navigationTitle("Matches")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let uuid):
                        ProfileDetailView(viewModel: makeDetailViewModel(uuid))
                    }
                }
        }
        .tint(style.accent)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingState

        case .empty:
            MessageState(
                symbol: "heart.text.square",
                title: "No matches yet",
                message: "Pull in a fresh batch and start deciding.",
                actionTitle: "Load matches"
            ) { Task { await viewModel.retry() } }

        case .failed(let message):
            MessageState(
                symbol: viewModel.isOnline ? "exclamationmark.triangle" : "wifi.slash",
                title: ProfileErrorText.loadFailedTitle,
                message: message,
                actionTitle: "Try again"
            ) { Task { await viewModel.retry() } }

        case .loaded(let rows, let footer):
            feed(rows: rows, footer: footer)
        }
    }

    private var loadingState: some View {
        VStack(spacing: style.spacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("Finding your matches…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading matches")
    }

    // MARK: - Feed

    private func feed(rows: [MatchRowUIModel], footer: MatchListFooter) -> some View {
        ScrollView {
            LazyVStack(spacing: style.spacing.l) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    MatchCardView(
                        row: row,
                        onOpen: { viewModel.openDetail(uuid: row.id) },
                        onDecision: { intent in
                            Task { await viewModel.apply(intent, uuid: row.id) }
                        }
                    )
                    // Prefetch trigger. Deliberately not `.task`, which would be
                    // cancelled the moment the row scrolls out of view and could
                    // tear down an in-flight page request.
                    .onAppear { Task { await viewModel.rowAppeared(at: index) } }
                }

                footerView(footer)
            }
            .padding(.horizontal, style.spacing.l)
            .padding(.top, style.spacing.xs)
            .padding(.bottom, style.spacing.xl)
            .animation(.default, value: rows)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.showsOfflineBanner {
                OfflineBanner(message: ProfileErrorText.offline)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: style.motion.bannerFade),
                   value: viewModel.showsOfflineBanner)
    }

    @ViewBuilder
    private func footerView(_ footer: MatchListFooter) -> some View {
        switch footer {
        case .idle:
            EmptyView()

        case .loadingMore:
            HStack(spacing: style.spacing.s) {
                ProgressView()
                Text("Loading more…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.spacing.l)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading more matches")

        case .failed(let message):
            VStack(spacing: style.spacing.s) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try again") { Task { await viewModel.retry() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(style.accent)
                    .accessibilityLabel("Try loading more matches again")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.spacing.l)
        }
    }
}

// MARK: - Small building blocks

/// Non-blocking connectivity notice. Shown only when there is cached content
/// behind it — with nothing cached the full-screen error is the right call.
@MainActor
struct OfflineBanner: View {
    @Environment(\.profileStyle) private var style
    let message: String

    var body: some View {
        HStack(spacing: style.spacing.s) {
            Image(systemName: "wifi.slash")
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, style.spacing.l)
        .padding(.vertical, style.spacing.m)
        .frame(maxWidth: .infinity)
        .background(style.banner.opacity(style.opacity.bannerFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. \(message)")
    }
}

@MainActor
struct MessageState: View {
    @Environment(\.profileStyle) private var style
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: style.spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: style.size.statusSymbol, weight: .light))
                .foregroundStyle(style.accent)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, style.spacing.m)
                    .padding(.horizontal, style.spacing.xl)
                    .background(Capsule().fill(style.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, style.spacing.xs)
        }
        .padding(style.spacing.xxl)
    }
}
