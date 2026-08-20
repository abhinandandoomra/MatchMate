import Foundation

/// What this API needs to be talked to. An instance, supplied at composition —
/// not a global namespace of constants that anything can reach into.
struct ProfileAPIConfig: Sendable {
    let baseURL: String
    let seed: String
    let pageSize: Int

    /// - Parameters:
    ///   - seed: keeps results stable across requests while the app is reviewed.
    ///   - pageSize: **must not vary between requests.** Verified against the
    ///     live API: `page` is not an offset into one stream — `page=2&results=10`
    ///     shares zero records with the last 10 of `page=1&results=20`. A page's
    ///     identity is the triple (seed, results, page), so changing this
    ///     re-partitions the dataset and silently corrupts cached pages.
    init(baseURL: String, seed: String, pageSize: Int = 10) {
        self.baseURL = baseURL
        self.seed = seed
        self.pageSize = pageSize
    }
}

/// The remote data source for profiles.
///
/// One responsibility: ask the HTTP client for a page and hand back the decoded
/// wire records. It does not translate to the domain — that is the repository's
/// job — and it does not know how the response is persisted or displayed.
protocol ProfileAPIServicing: Sendable {
    func profiles(page: Int) async throws(NetworkError) -> [ProfileDTO]
}

struct ProfileAPIService: ProfileAPIServicing {
    private let config: ProfileAPIConfig
    private let client: any HTTPClient

    init(config: ProfileAPIConfig, client: any HTTPClient) {
        self.config = config
        self.client = client
    }

    func profiles(page: Int) async throws(NetworkError) -> [ProfileDTO] {
        let endpoint = Endpoint<ProfileListDTO>(
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "results", value: String(config.pageSize)),
                URLQueryItem(name: "seed", value: config.seed)
            ]
        )
        return try await client.send(endpoint).results
    }
}
