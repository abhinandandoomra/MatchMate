import Foundation

extension JSONDecoder {

    /// A decoder for APIs that emit ISO8601 timestamps **with** fractional
    /// seconds — `"1945-10-14T19:53:33.877Z"`.
    ///
    /// Needed because on iOS 18 the built-in `.iso8601` strategy omits
    /// `.withFractionalSeconds` and fails outright on those. Newer runtimes
    /// parse them fine, which makes this easy to "verify" away on a modern
    /// simulator and then break on the oldest OS the app supports.
    ///
    /// Fractional is tried first and plain second, so the decoder survives the
    /// API dropping the fraction as well as sending it.
    ///
    /// `Date.ISO8601FormatStyle` is a value type, so the two styles can be
    /// captured directly. The equivalent with `ISO8601DateFormatter` would need
    /// shared class instances and a `nonisolated(unsafe)` opt-out of Swift 6's
    /// concurrency checking.
    static func iso8601FractionalSeconds() -> JSONDecoder {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let withoutFraction = Date.ISO8601FormatStyle()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = try? withFraction.parse(raw) { return date }
            guard let date = try? withoutFraction.parse(raw) else {
                throw NetworkError.decoding
            }
            return date
        }
        return decoder
    }
}
