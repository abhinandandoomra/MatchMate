import Foundation

/// Fetching raw image bytes, kept as its own seam so a feature can be handed
/// image loading without also being handed the whole HTTP client.
protocol ImageFetching: Sendable {
    func fetch(_ url: URL) async throws(NetworkError) -> Data
}
