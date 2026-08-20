import Foundation
import Testing
@testable import MatchMate

struct ProfileMapperTests {

    private func makeDTO() throws -> ProfileDTO {
        let json = """
        {"results":[{
          "gender":"female",
          "name":{"title":"Miss","first":"Nalan","last":"Akgul"},
          "location":{"city":"Van","state":"Hakkari","country":"Turkey","postcode":40291},
          "email":"nalan@example.com",
          "login":{"uuid":"uuid-abc"},
          "dob":{"date":"1992-11-15T17:18:48.276Z","age":33},
          "registered":{"date":"2015-01-19T08:46:16.565Z","age":11},
          "phone":"(590)-971-8437","cell":"(121)-414-5321",
          "id":{"name":"","value":null},
          "picture":{"large":"https://randomuser.me/api/portraits/women/21.jpg"},
          "nat":"TR"
        }]}
        """
        return try JSONDecoder.iso8601FractionalSeconds()
            .decode(ProfileListDTO.self, from: Data(json.utf8)).results[0]
    }

    @Test("maps identity and API-owned fields")
    func mapsFields() throws {
        let profile = ProfileMapper().toDomain(try makeDTO(), page: 3, index: 7)
        #expect(profile.uuid == "uuid-abc")
        #expect(profile.fullName == "Nalan Akgul")
        #expect(profile.email == "nalan@example.com")
        #expect(profile.nationalityCode == "TR")
        #expect(profile.city == "Van")
        #expect(profile.country == "Turkey")
    }

    @Test("stamps the page coordinates that give the list its stable order")
    func stampsOrdering() throws {
        let profile = ProfileMapper().toDomain(try makeDTO(), page: 3, index: 7)
        #expect(profile.sourcePage == 3)   // D-23 — the derived cursor reads this
        #expect(profile.indexInPage == 7)  // D-24 — half of the sort key
    }

    @Test("a freshly fetched profile is always pending and carries no bytes")
    func defaults() throws {
        let profile = ProfileMapper().toDomain(try makeDTO(), page: 1, index: 0)
        #expect(profile.status == .pending)
        #expect(profile.decidedAt == nil)
        #expect(profile.imageData == nil)
    }
}
