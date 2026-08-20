import Foundation
import Testing
@testable import MatchMate

struct NetworkErrorTests {

    @Test("only transient failures are retried")
    func retryability() {
        #expect(NetworkError.timeout.isRetryable)
        #expect(NetworkError.server(status: 500).isRetryable)
        #expect(NetworkError.rateLimited(retryAfter: 2).isRetryable)
        #expect(NetworkError.offline.isRetryable == false)
        #expect(NetworkError.decoding.isRetryable == false)
        #expect(NetworkError.cancelled.isRetryable == false)
    }

    @Test("URLError maps to the right domain error")
    func urlErrorMapping() {
        #expect(NetworkError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(NetworkError.from(URLError(.networkConnectionLost)) == .offline)
        #expect(NetworkError.from(URLError(.timedOut)) == .timeout)
    }

    @Test("decoding failures are classified, not swallowed")
    func decodingMapping() {
        let error = DecodingError.valueNotFound(
            String.self, .init(codingPath: [], debugDescription: "x"))
        #expect(NetworkError.from(error) == .decoding)
    }

    @Test("an NetworkError passes through unchanged")
    func passthrough() {
        #expect(NetworkError.from(NetworkError.offline) == .offline)
    }

    @Test("retryAfter is only carried by rateLimited")
    func retryAfter() {
        #expect(NetworkError.rateLimited(retryAfter: 5).retryAfter == 5)
        #expect(NetworkError.timeout.retryAfter == nil)
    }
}

extension NetworkErrorTests {

    @Test("a 4xx is a stable answer and is not retried")
    func clientErrorsAreNotRetried() {
        #expect(NetworkError.server(status: 404).isRetryable == false)
        #expect(NetworkError.server(status: 400).isRetryable == false)
    }

    @Test("5xx and unclassified transport errors are retried")
    func serverErrorsAreRetried() {
        #expect(NetworkError.server(status: 500).isRetryable)
        #expect(NetworkError.server(status: 503).isRetryable)
        #expect(NetworkError.server(status: -1).isRetryable)
    }
}
