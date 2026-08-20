import Foundation

/// Exponential backoff around a single throwing operation.
///
/// The clock is injected rather than calling `Task.sleep` directly so tests can
/// exhaust every attempt instantly instead of waiting 3.5 real seconds.
struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval

    /// 3 attempts / 0.5s base — 0.5s, then 1s, then give up.
    static let `default` = RetryPolicy()

    /// One attempt, no backoff — for calls where failing fast beats persisting.
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0)

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
    }

    /// Runs `operation`, retrying only failures that another attempt could fix.
    ///
    /// - `NetworkError.isRetryable` is the sole gate: a decoding failure or a
    ///   genuine offline state repeats identically, so retrying only delays the
    ///   error the UI needs to show.
    /// - A server-supplied `Retry-After` always wins over the computed backoff —
    ///   racing ahead of it just earns another 429.
    /// - Cancellation is rethrown untouched. `NetworkError.from` would flatten it
    ///   into `.server(status: -1)` and a cancelled scroll would surface as a
    ///   network failure.
    func run<T: Sendable>(
        clock: any AppClock,
        _ operation: @Sendable () async throws -> T
    ) async throws(NetworkError) -> T {
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                let failure = NetworkError.from(error)
                guard failure.isRetryable, attempt < maxAttempts else { throw failure }

                // Checked before sleeping so a cancelled task exits during the
                // backoff window rather than after the next request lands.
                if Task.isCancelled { throw NetworkError.cancelled }
                do {
                    try await clock.sleep(for: failure.retryAfter ?? delay(forAttempt: attempt))
                } catch {
                    throw NetworkError.cancelled
                }
                attempt += 1
            }
        }
    }

    /// 0.5s, 1s, 2s, ... — `attempt` is 1-based.
    private func delay(forAttempt attempt: Int) -> TimeInterval {
        baseDelay * pow(2, Double(attempt - 1))
    }
}
