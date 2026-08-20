import Foundation

/// Everything the transport can fail with — and nothing else.
///
/// Deliberately carries no user-facing copy: infrastructure describes *what*
/// went wrong, the presentation layer decides how to say it.
enum NetworkError: Error, Equatable, Sendable {
    case offline
    case timeout
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case decoding
    /// The request was cancelled — a scroll away, a screen dismissal. Not a
    /// failure the user should ever be told about.
    case cancelled

    /// Retry is a transport concern, so the policy lives with the transport's
    /// own vocabulary rather than in a shared app-wide enum.
    ///
    /// A 4xx is a stable answer — retrying it burns the budget and delays the
    /// error the user actually needs to see.
    var isRetryable: Bool {
        switch self {
        case .timeout, .rateLimited: true
        case .server(let status): status >= 500 || status < 0
        case .offline, .decoding, .cancelled: false
        }
    }

    var retryAfter: TimeInterval? {
        if case .rateLimited(let after) = self { return after }
        return nil
    }

    static func from(_ error: any Error) -> NetworkError {
        if let network = error as? NetworkError { return network }
        if error is CancellationError { return .cancelled }
        if error is DecodingError { return .decoding }
        guard let urlError = error as? URLError else { return .server(status: -1) }
        return switch urlError.code {
        // URLSession reports task cancellation as a URLError, not a
        // CancellationError, so both spellings have to land on .cancelled.
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost,
             .dataNotAllowed, .internationalRoamingOff: .offline
        case .timedOut: .timeout
        default: .server(status: -1)
        }
    }
}
