import Foundation
import Testing
@testable import MatchMate

struct ProfileAPIServiceTests {

    private func makeAPI(_ server: StubServer, clock: StubClock) -> ProfileAPIService {
        ProfileAPIService(
            config: .test,
            client: URLSessionHTTPClient(
                baseURL: ProfileAPIConfig.test.baseURL,
                decoder: .iso8601FractionalSeconds(),
                session: server.session,
                clock: clock
            )
        )
    }

    private func payload(count: Int = 2) -> Data {
        let records = (0..<count).map { index in
            """
            {"gender":"female",
             "name":{"title":"Miss","first":"F\(index)","last":"L\(index)"},
             "location":{"city":"Van","state":"Hakkari","country":"Turkey","postcode":40291},
             "email":"e\(index)@example.com","login":{"uuid":"u-\(index)"},
             "dob":{"date":"1992-11-15T17:18:48.276Z","age":33},
             "registered":{"date":"2015-01-19T08:46:16.565Z","age":11},
             "phone":"p","cell":"c","id":{"name":"","value":null},
             "picture":{"large":"https://randomuser.me/api/portraits/women/\(index).jpg"},
             "nat":"TR"}
            """
        }
        return Data("{\"results\":[\(records.joined(separator: ","))]}".utf8)
    }

    // MARK: - Request construction (C-1)

    @Test("the request carries the fixed seed and page size — C-1")
    func requestQuery() async throws {
        let server = StubServer()
        let api = makeAPI(server, clock: StubClock())
        server.enqueue(.init(body: payload()))
        _ = try await api.profiles(page: 3)

        let url = try #require(server.recordedURLs.first)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(url.host == "randomuser.me")
        #expect(byName["page"] == "3")
        #expect(byName["results"] == String(ProfileAPIConfig.test.pageSize))   // never a literal
        #expect(byName["seed"] == ProfileAPIConfig.test.seed)
    }

    @Test("results is always 10 whatever page is asked for")
    func pageSizeIsConstant() async throws {
        let server = StubServer()
        let api = makeAPI(server, clock: StubClock())
        for _ in 1...3 { server.enqueue(.init(body: payload())) }
        for page in 1...3 { _ = try await api.profiles(page: page) }

        for url in server.recordedURLs {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.first { $0.name == "results" }?.value == "10")
        }
    }

    // MARK: - Success

    @Test("a 200 decodes into wire records")
    func decodesSuccess() async throws {
        let server = StubServer()
        let api = makeAPI(server, clock: StubClock())
        server.enqueue(.init(body: payload(count: 4)))
        let dtos = try await api.profiles(page: 1)

        #expect(dtos.count == 4)
        #expect(dtos[0].login.uuid == "u-0")
        #expect(dtos[0].name.first == "F0")
    }



    // MARK: - Failure mapping

    @Test("a 500 maps to .server and is retried to exhaustion")
    func serverErrorRetries() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        for _ in 0..<3 { server.enqueue(.init(status: 500)) }

        await #expect(throws: NetworkError.server(status: 500)) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays() == [0.5, 1.0])
    }

    @Test("a 404 is not retried — it is a stable answer")
    func notFoundDoesNotRetry() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        server.enqueue(.init(status: 404))

        await #expect(throws: NetworkError.server(status: 404)) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays().isEmpty)
        #expect(server.recordedURLs.count == 1)
    }

    @Test("a 429 carries Retry-After through to the backoff")
    func rateLimited() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        for _ in 0..<3 { server.enqueue(.init(status: 429, headers: ["Retry-After": "4"])) }

        await #expect(throws: NetworkError.rateLimited(retryAfter: 4)) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays() == [4, 4])
    }

    @Test("losing the connection maps to .offline and is not retried")
    func offlineMapping() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        server.enqueue(.init(error: URLError(.notConnectedToInternet)))

        await #expect(throws: NetworkError.offline) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays().isEmpty)
    }

    @Test("a timeout is retried")
    func timeoutRetries() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        for _ in 0..<3 { server.enqueue(.init(error: URLError(.timedOut))) }

        await #expect(throws: NetworkError.timeout) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays() == [0.5, 1.0])
    }

    @Test("malformed JSON surfaces as .decoding and is never retried")
    func malformedBody() async {
        let clock = StubClock()
        let server = StubServer()
        let api = makeAPI(server, clock: clock)
        server.enqueue(.init(body: Data("{\"results\":[{".utf8)))

        await #expect(throws: NetworkError.decoding) { _ = try await api.profiles(page: 1) }
        #expect(await clock.delays().isEmpty)
        #expect(server.recordedURLs.count == 1)
    }

    @Test("a transient failure followed by success returns data")
    func recoversAfterRetry() async throws {
        let server = StubServer()
        let api = makeAPI(server, clock: StubClock())
        server.enqueue(.init(status: 503))
        server.enqueue(.init(body: payload(count: 1)))

        let dtos = try await api.profiles(page: 1)
        #expect(dtos.count == 1)
        #expect(server.recordedURLs.count == 2)
    }
}

struct HTTPImageFetcherTests {

    private func makeFetcher(_ server: StubServer, clock: StubClock = StubClock()) -> HTTPImageFetcher {
        HTTPImageFetcher(client: URLSessionHTTPClient(
            baseURL: ProfileAPIConfig.test.baseURL,
            decoder: .iso8601FractionalSeconds(),
            session: server.session,
            clock: clock
        ))
    }

    @Test("returns the bytes the server sent")
    func fetchesBytes() async throws {
        let server = StubServer()
        server.enqueue(.init(body: Data([0xFF, 0xD8, 0xFF, 0xE0])))

        let data = try await makeFetcher(server).fetch(URL(string: "https://randomuser.me/a.jpg")!)
        #expect(data == Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    @Test("a transport failure surfaces as a typed error")
    func mapsFailure() async {
        let server = StubServer()
        server.enqueue(.init(error: URLError(.notConnectedToInternet)))

        await #expect(throws: NetworkError.offline) {
            _ = try await makeFetcher(server).fetch(URL(string: "https://randomuser.me/a.jpg")!)
        }
    }

    /// Portraits must not retry — three attempts per image would triple a page
    /// load on a flaky connection for something purely cosmetic.
    @Test("a failed portrait is attempted exactly once")
    func doesNotRetry() async {
        let server = StubServer()
        let clock = StubClock()
        for _ in 0..<3 { server.enqueue(.init(status: 500)) }

        await #expect(throws: NetworkError.server(status: 500)) {
            _ = try await makeFetcher(server, clock: clock).fetch(URL(string: "https://randomuser.me/a.jpg")!)
        }
        #expect(server.recordedURLs.count == 1)
        #expect(await clock.delays().isEmpty)
    }
}

/// The query the service actually puts on the wire. Endpoint construction is
/// internal to `ProfileAPIService` now, so it is verified through the request
/// rather than by inspecting a value.
struct ProfileAPIRequestTests {

    private func recordQuery(page: Int) async throws -> [String: String] {
        let server = StubServer()
        let api = ProfileAPIService(
            config: .test,
            client: URLSessionHTTPClient(
                baseURL: ProfileAPIConfig.test.baseURL,
                decoder: .iso8601FractionalSeconds(),
                session: server.session,
                clock: StubClock()
            )
        )
        server.enqueue(.init(body: Data("{\"results\":[]}".utf8)))
        _ = try await api.profiles(page: page)

        let url = try #require(server.recordedURLs.first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("results is pinned to the configured page size", arguments: [1, 2, 7, 500])
    func pageSizeIsPinned(page: Int) async throws {
        let query = try await recordQuery(page: page)
        #expect(query["results"] == String(ProfileAPIConfig.test.pageSize))
        #expect(query["results"] == "10")
    }

    @Test("seed is pinned so results stay stable across a review")
    func seedIsPinned() async throws {
        #expect(try await recordQuery(page: 1)["seed"] == ProfileAPIConfig.test.seed)
    }

    @Test("page is the only thing that varies between requests")
    func pageVaries() async throws {
        #expect(try await recordQuery(page: 3)["page"] == "3")
        #expect(try await recordQuery(page: 9)["page"] == "9")
    }
}

/// Copy now lives in the presentation layer, so it is assertable — the error
/// types themselves carry no user-facing strings.
struct ProfileErrorTextTests {

    @Test("every reportable network failure has copy", arguments: [
        NetworkError.offline, .timeout, .rateLimited(retryAfter: nil),
        .server(status: 500), .decoding
    ])
    func networkMessages(error: NetworkError) {
        #expect(ProfileErrorText.message(for: error).isEmpty == false)
    }

    @Test("every persistence failure has copy", arguments: [
        PersistenceError.unavailable, .notFound, .operationFailed
    ])
    func persistenceMessages(error: PersistenceError) {
        #expect(ProfileErrorText.message(for: error).isEmpty == false)
    }

    @Test("a wrapped error resolves to its underlying copy")
    func wrappedResolves() {
        #expect(ProfileErrorText.message(for: .network(.timeout))
                == ProfileErrorText.message(for: NetworkError.timeout))
        #expect(ProfileErrorText.message(for: .persistence(.notFound))
                == ProfileErrorText.profileUnavailable)
    }

    /// A cancelled load is filtered before it reaches a view, so it is the one
    /// case with deliberately empty copy.
    @Test("cancellation carries no user-facing copy")
    func cancellationHasNoCopy() {
        #expect(ProfileErrorText.message(for: NetworkError.cancelled).isEmpty)
    }
}

/// A scroll-away cancels the in-flight request. Before typed throws forced the
/// issue, that surfaced to the user as "The server couldn't be reached."
struct CancellationTests {

    @Test("URLSession cancellation is classified as cancelled, not a server fault")
    func urlErrorCancelled() {
        #expect(NetworkError.from(URLError(.cancelled)) == .cancelled)
    }

    @Test("a Swift CancellationError is classified the same way")
    func swiftCancellation() {
        #expect(NetworkError.from(CancellationError()) == .cancelled)
    }

    @Test("cancellation is never retried")
    func notRetried() {
        #expect(NetworkError.cancelled.isRetryable == false)
    }

    @Test("a cancelled page load is not reported to the user")
    @MainActor
    func cancelledLoadIsSilent() async {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(), api: StubProfileAPI(error: .cancelled),
            images: StubImageFetcher())
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity())

        await vm.onAppear()

        #expect(vm.pageError == nil)
        #expect(vm.state != .failed(message: ProfileErrorText.message(for: NetworkError.cancelled)))
    }

    @Test("a genuine failure still is reported")
    @MainActor
    func realFailureIsReported() async {
        let repo = ProfileRepositoryImpl(
            store: StubProfileStore(), api: StubProfileAPI(error: .timeout),
            images: StubImageFetcher())
        let vm = MatchListViewModel(repo: repo, connectivity: StubConnectivity())

        await vm.onAppear()

        #expect(vm.pageError == .network(.timeout))
    }
}

struct SystemClockTests {

    @Test("the real clock actually waits")
    func sleeps() async throws {
        let start = Date()
        try await SystemClock().sleep(for: 0.05)
        #expect(Date().timeIntervalSince(start) >= 0.04)
    }
}
