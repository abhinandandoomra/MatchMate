import Foundation

/// The only place in the app that talks to `URLSession`.
///
/// Knows nothing about any particular API: the base URL is supplied at
/// composition, and endpoints carry their own paths and queries.
///
/// URL construction, status validation, decoding and retry all happen here, so
/// an endpoint is reduced to the data that distinguishes it. The base URL and
/// The base URL and decoder are supplied at construction, so nothing about any
/// particular API is baked in — a second API is a second instance, not a change
/// here.
struct URLSessionHTTPClient: HTTPClient {
    private let baseURL: String
    private let decoder: JSONDecoder
    private let session: URLSession
    private let clock: any AppClock

    init(
        baseURL: String,
        decoder: JSONDecoder,
        session: URLSession = .shared,
        clock: any AppClock = SystemClock()
    ) {
        self.baseURL = baseURL
        self.decoder = decoder
        self.session = session
        self.clock = clock
    }

    func send<Response>(_ endpoint: Endpoint<Response>, retry: RetryPolicy) async throws(NetworkError) -> Response {
        let url = try makeURL(for: endpoint)
        return try await retry.run(clock: clock) {
            let data = try await fetch(url)
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw NetworkError.decoding
            }
        }
    }

    func data(from url: URL, retry: RetryPolicy) async throws(NetworkError) -> Data {
        try await retry.run(clock: clock) { try await fetch(url) }
    }

    // MARK: - Transport

    private func fetch(_ url: URL) async throws(NetworkError) -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            try Self.validate(response)
            return data
        } catch {
            // Normalised here so `RetryPolicy` can read `isRetryable` and
            // callers only ever see `NetworkError`.
            throw NetworkError.from(error)
        }
    }

    private func makeURL<Response>(for endpoint: Endpoint<Response>) throws(NetworkError) -> URL {
        guard var components = URLComponents(string: baseURL + endpoint.path) else {
            throw NetworkError.server(status: -1)
        }
        components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components.url else { throw NetworkError.server(status: -1) }
        return url
    }

    // MARK: - Response

    private static func validate(_ response: URLResponse) throws(NetworkError) {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.server(status: -1)
        }
        switch http.statusCode {
        case 200..<300: return
        case 429:       throw NetworkError.rateLimited(retryAfter: retryAfter(from: http))
        default:        throw NetworkError.server(status: http.statusCode)
        }
    }

    /// `Retry-After` in delta-seconds. The HTTP-date form is ignored rather
    /// than mis-parsed; the policy then falls back to its own backoff.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return nil }
        return seconds
    }
}
