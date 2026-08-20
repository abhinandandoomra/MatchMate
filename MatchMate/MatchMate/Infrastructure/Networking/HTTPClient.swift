import Foundation

/// A request described as data rather than code.
///
/// The response type travels with the endpoint, so `HTTPClient.send` needs no
/// casting and no per-call decoder wiring. Endpoints are pure values, which
/// means the query a request will produce can be asserted in a unit test
/// without a network stub at all.
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let query: [URLQueryItem]

    init(path: String = "", query: [URLQueryItem] = []) {
        self.path = path
        self.query = query
    }
}

/// The single transport seam. Retry, status validation and decoding live behind
/// this one protocol rather than being repeated per endpoint.
protocol HTTPClient: Sendable {
    func send<Response>(_ endpoint: Endpoint<Response>, retry: RetryPolicy) async throws(NetworkError) -> Response
    func data(from url: URL, retry: RetryPolicy) async throws(NetworkError) -> Data
}

extension HTTPClient {
    func send<Response>(_ endpoint: Endpoint<Response>) async throws(NetworkError) -> Response {
        try await send(endpoint, retry: .default)
    }

    /// Portraits deliberately do not retry: a missed one is cosmetic, the
    /// repository already treats the fetch as best-effort, and three attempts
    /// per image would multiply a page load by three on a flaky connection.
    func data(from url: URL) async throws(NetworkError) -> Data {
        try await data(from: url, retry: .none)
    }
}
