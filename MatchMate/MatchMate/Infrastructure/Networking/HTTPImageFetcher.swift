import Foundation

/// Portrait bytes over the shared transport.
///
/// Kept behind `ImageFetching` rather than handing the repository a raw
/// `HTTPClient`, so image fetching stays trivially stubbable and the repository
/// cannot accidentally reach the JSON endpoints.
struct HTTPImageFetcher: ImageFetching {
    private let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    /// No retry: a missed portrait is cosmetic and the repository already
    /// treats this as best-effort (F-10).
    func fetch(_ url: URL) async throws(NetworkError) -> Data {
        try await client.data(from: url, retry: .none)
    }
}
