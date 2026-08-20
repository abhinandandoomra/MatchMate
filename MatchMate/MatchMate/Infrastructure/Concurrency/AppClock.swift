import Foundation

/// Injected so retry backoff is instant in tests instead of sleeping in real time.
/// Named `AppClock` to avoid colliding with the standard library's `Clock`.
protocol AppClock: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

struct SystemClock: AppClock {
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
