import Foundation
@testable import MatchMate

extension ProfileAPIConfig {
    /// The configuration under test, matching what composition builds.
    static let test = ProfileAPIConfig(baseURL: "https://randomuser.me/api/", seed: "matchmate")
}

enum DTOFactory {
    /// Builds DTOs by decoding real-shaped JSON rather than via memberwise init,
    /// so fixtures exercise the same decoder the app uses.
    static func page(_ page: Int, count: Int = ProfileAPIConfig.test.pageSize) throws -> [ProfileDTO] {
        let records = (0..<count).map { index -> String in
            """
            {"gender":"female",
             "name":{"title":"Miss","first":"First\(page)-\(index)","last":"Last\(page)-\(index)"},
             "location":{"city":"Van","state":"Hakkari","country":"Turkey","postcode":40291},
             "email":"p\(page)i\(index)@example.com",
             "login":{"uuid":"uuid-\(page)-\(index)"},
             "dob":{"date":"1992-11-15T17:18:48.276Z","age":33},
             "registered":{"date":"2015-01-19T08:46:16.565Z","age":11},
             "phone":"(590)-971-8437","cell":"(121)-414-5321",
             "id":{"name":"","value":null},
             "picture":{"large":"https://randomuser.me/api/portraits/women/\(index).jpg"},
             "nat":"TR"}
            """
        }
        let json = "{\"results\":[\(records.joined(separator: ","))]}"
        return try JSONDecoder.iso8601FractionalSeconds()
            .decode(ProfileListDTO.self, from: Data(json.utf8)).results
    }
}

/// Returns wire records, like the real service — translation is the
/// repository's job, so the stub must not do it either.
actor StubProfileAPI: ProfileAPIServicing {
    private(set) var requestedPages: [Int] = []
    private var error: NetworkError?
    private let pageSize: Int

    init(error: NetworkError? = nil, pageSize: Int = ProfileAPIConfig.test.pageSize) {
        self.error = error
        self.pageSize = pageSize
    }

    func fail(with error: NetworkError?) { self.error = error }
    func pages() -> [Int] { requestedPages }

    func profiles(page: Int) async throws(NetworkError) -> [ProfileDTO] {
        requestedPages.append(page)
        if let error { throw error }
        guard let dtos = try? DTOFactory.page(page, count: pageSize) else {
            throw NetworkError.decoding
        }
        return dtos
    }
}
