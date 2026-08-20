import Foundation

/// Intercepts URLSession traffic so network tests never touch the network (NFR-06).
///
/// `URLProtocol` subclasses are registered process-wide, and Swift Testing runs
/// suites in parallel — so state is keyed by a per-session token rather than
/// shared statically. Without that, concurrent tests consume each other's
/// queued responses.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]
        var error: URLError?
    }

    static let tokenHeader = "X-Stub-Token"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Response]] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URL]] = [:]

    static func register(_ token: String) {
        lock.withLock { queues[token] = []; recorded[token] = [] }
    }
    static func unregister(_ token: String) {
        lock.withLock { queues[token] = nil; recorded[token] = nil }
    }
    static func enqueue(_ response: Response, for token: String) {
        lock.withLock { queues[token, default: []].append(response) }
    }
    static func urls(for token: String) -> [URL] {
        lock.withLock { recorded[token] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: tokenHeader) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: Self.tokenHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let next: Response = Self.lock.withLock {
            if let url = self.request.url { Self.recorded[token, default: []].append(url) }
            var queue = Self.queues[token] ?? []
            let head = queue.isEmpty ? Response() : queue.removeFirst()
            Self.queues[token] = queue
            return head
        }

        if let error = next.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status,
            httpVersion: "HTTP/1.1", headerFields: next.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// One isolated fake server per test.
final class StubServer {
    let token = UUID().uuidString
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [StubURLProtocol.tokenHeader: token]
        session = URLSession(configuration: configuration)
        StubURLProtocol.register(token)
    }

    func enqueue(_ response: StubURLProtocol.Response) {
        StubURLProtocol.enqueue(response, for: token)
    }
    var recordedURLs: [URL] { StubURLProtocol.urls(for: token) }

    deinit { StubURLProtocol.unregister(token) }
}
