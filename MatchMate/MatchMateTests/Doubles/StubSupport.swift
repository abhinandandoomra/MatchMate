import Foundation
@testable import MatchMate

/// Records requested delays and returns immediately, so backoff tests finish in
/// microseconds instead of sleeping for the real 0.5 + 1 + 2 seconds.
actor StubClock: AppClock {
    private(set) var requestedDelays: [TimeInterval] = []
    func sleep(for seconds: TimeInterval) async throws { requestedDelays.append(seconds) }
    func delays() -> [TimeInterval] { requestedDelays }
}

final class StubImageFetcher: ImageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [URL] = []
    private let result: Result<Data, NetworkError>

    init(result: Result<Data, NetworkError> = .success(Data([0xFF, 0xD8]))) { self.result = result }

    var requested: [URL] { lock.withLock { _requested } }

    func fetch(_ url: URL) async throws(NetworkError) -> Data {
        lock.withLock { _requested.append(url) }
        return try result.get()
    }
}

struct StubConnectivity: ConnectivityMonitoring {
    let online: Bool
    init(online: Bool = true) { self.online = online }
    var isOnline: Bool { get async { online } }
    func stream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(online)
            continuation.finish()
        }
    }
}

extension Profile {
    static func fixture(
        uuid: String = "uuid-1",
        firstName: String = "Nalan",
        lastName: String = "Akgul",
        sourcePage: Int = 1,
        indexInPage: Int = 0,
        status: DecisionStatus = .pending,
        imageData: Data? = nil,
        dateOfBirth: Date = Date(timeIntervalSince1970: 721_500_000),
        nationalityCode: String = "TR",
        city: String = "Van",
        country: String = "Turkey"
    ) -> Profile {
        Profile(
            uuid: uuid, firstName: firstName, lastName: lastName,
            email: "\(firstName.lowercased())@example.com",
            phone: "(590)-971-8437", cell: "(121)-414-5321",
            gender: "female", nationalityCode: nationalityCode,
            dateOfBirth: dateOfBirth,
            registeredAt: Date(timeIntervalSince1970: 1_421_657_176),
            city: city, state: "Hakkari", country: country,
            pictureURL: URL(string: "https://randomuser.me/api/portraits/women/21.jpg")!,
            sourcePage: sourcePage, indexInPage: indexInPage,
            imageData: imageData, status: status, decidedAt: nil
        )
    }
}
