import SwiftUI

@main
@MainActor
struct MatchMateApp: App {

    /// Composed once, at launch. `nil` means the local store could not be
    /// opened — corrupt, migration-incompatible, or no room on disk.
    private let repository = try? makeRepository()

    var body: some Scene {
        WindowGroup {
            if let repository {
                MatchListScreen(repository: repository)
            } else {
                StoreUnavailableView()
            }
        }
    }
}

/// The composition root: the one place concrete implementations are chosen.
///
/// A free function rather than a member of `MatchMateApp`, for two reasons.
/// `repository` is a property initializer, which runs before `self` exists and
/// therefore cannot call an instance method — and composition is not really a
/// behaviour of the App type, it is the wiring that happens to run at launch.
///
/// Nothing below this line constructs its own dependencies, which is what keeps
/// every type injectable — and, critically, what lets the list and the detail
/// screen share ONE `ProfileRepository`. That shared instance is the whole of
/// the list/detail consistency mechanism: no notifications, no
/// refresh-on-appear.
///
/// A single HTTP client backs both the JSON endpoints and the portraits, so the
/// two share one connection pool and cache.
@MainActor
private func makeRepository() throws(PersistenceError) -> any ProfileRepository {
    let config = ProfileAPIConfig(
        baseURL: "https://randomuser.me/api/",
        seed: "matchmate"
    )
    let client = URLSessionHTTPClient(
        baseURL: config.baseURL,
        decoder: .iso8601FractionalSeconds()
    )

    return ProfileRepositoryImpl(
        store: try SwiftDataProfileStore(),
        api: ProfileAPIService(config: config, client: client),
        images: HTTPImageFetcher(client: client)
    )
}

/// Shown when composition failed. Deliberately terminal: relaunching is the
/// real remedy for a store that will not open.
@MainActor
struct StoreUnavailableView: View {
    @Environment(\.profileStyle) private var style
    var body: some View {
        VStack(spacing: style.spacing.m) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: style.size.statusSymbol, weight: .light))
                .foregroundStyle(style.accent)
            Text(ProfileErrorText.startupFailedTitle)
                .font(.title3.weight(.semibold))
            Text(ProfileErrorText.message(for: PersistenceError.unavailable))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(style.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.screenBackground)
    }
}
