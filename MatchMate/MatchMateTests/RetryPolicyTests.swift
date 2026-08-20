import Foundation
import Testing
@testable import MatchMate

struct RetryPolicyTests {

    @Test("a successful call is not retried")
    func succeedsFirstTry() async throws {
        let clock = StubClock()
        let count = Counter()
        let value = try await RetryPolicy.default.run(clock: clock) {
            await count.bump()
            return 42
        }
        #expect(value == 42)
        #expect(await count.value == 1)
        #expect(await clock.delays().isEmpty)
    }

    @Test("a transient failure is retried with exponential backoff")
    func retriesWithBackoff() async {
        let clock = StubClock()
        let count = Counter()
        await #expect(throws: NetworkError.timeout) {
            try await RetryPolicy.default.run(clock: clock) {
                await count.bump()
                throw NetworkError.timeout
            }
        }
        #expect(await count.value == 3)                  // D-27 — three attempts
        #expect(await clock.delays() == [0.5, 1.0])      // 0.5s then 1s between them
    }

    @Test("it stops retrying as soon as the call succeeds")
    func stopsOnSuccess() async throws {
        let clock = StubClock()
        let count = Counter()
        let value = try await RetryPolicy.default.run(clock: clock) {
            let attempt = await count.bump()
            if attempt == 1 { throw NetworkError.server(status: 503) }
            return "ok"
        }
        #expect(value == "ok")
        #expect(await count.value == 2)
        #expect(await clock.delays() == [0.5])
    }

    @Test("a non-retryable failure fails immediately")
    func doesNotRetryDecoding() async {
        let clock = StubClock()
        let count = Counter()
        await #expect(throws: NetworkError.decoding) {
            try await RetryPolicy.default.run(clock: clock) {
                await count.bump()
                throw NetworkError.decoding
            }
        }
        #expect(await count.value == 1)
        #expect(await clock.delays().isEmpty)
    }

    @Test("offline is not retried — the monitor already knows")
    func doesNotRetryOffline() async {
        let clock = StubClock()
        let count = Counter()
        await #expect(throws: NetworkError.offline) {
            try await RetryPolicy.default.run(clock: clock) {
                await count.bump()
                throw NetworkError.offline
            }
        }
        #expect(await count.value == 1)
    }

    @Test("Retry-After overrides the computed backoff")
    func honoursRetryAfter() async {
        let clock = StubClock()
        await #expect(throws: NetworkError.rateLimited(retryAfter: 7)) {
            try await RetryPolicy.default.run(clock: clock) {
                throw NetworkError.rateLimited(retryAfter: 7)
            }
        }
        #expect(await clock.delays() == [7, 7])
    }
}

actor Counter {
    private(set) var value = 0
    @discardableResult func bump() -> Int { value += 1; return value }
}
