import Foundation
import Testing
@testable import MatchMate

/// The payload still contains fields this app does not model — `postcode`
/// (an `Int` on some records, a `String` on others), `id.value` (`null` on
/// roughly one in four), `name.title`, `dob.age`. None are declared, so none
/// need decoding strategies. These tests pin that: the record decodes whatever
/// shape those keys take, because they are never read.
struct ProfileDTODecodingTests {

    private static func record(postcode: String, idValue: String, dob: String) -> String {
        """
        {"results":[{
          "gender":"female",
          "name":{"title":"Miss","first":"Nalan","last":"Akgul"},
          "location":{"street":{"number":380,"name":"Anafartalar Cd"},
                      "city":"Van","state":"Hakkari","country":"Turkey",
                      "postcode":\(postcode),
                      "coordinates":{"latitude":"71.7403","longitude":"160.6450"},
                      "timezone":{"offset":"+10:00","description":"Vladivostok"}},
          "email":"nalan@example.com",
          "login":{"uuid":"b14f01c5-57dc-4023-be26-fbda38e1fc2d","username":"happywolf745"},
          "dob":{"date":"\(dob)","age":33},
          "registered":{"date":"2015-01-19T08:46:16.565Z","age":11},
          "phone":"(590)-971-8437","cell":"(121)-414-5321",
          "id":{"name":"","value":\(idValue)},
          "picture":{"large":"https://randomuser.me/api/portraits/women/21.jpg",
                     "medium":"https://randomuser.me/api/portraits/med/women/21.jpg"},
          "nat":"TR"
        }]}
        """
    }

    private static var decoder: JSONDecoder { .iso8601FractionalSeconds() }

    private static func decodeRecord(postcode: String = "40291",
                                     idValue: String = "null",
                                     dob: String = "1992-11-15T17:18:48.276Z") throws -> ProfileDTO {
        let json = record(postcode: postcode, idValue: idValue, dob: dob)
        return try decoder.decode(ProfileListDTO.self, from: Data(json.utf8)).results[0]
    }

    // MARK: - Fields we never read cannot break us

    @Test("an Int postcode is irrelevant — the field is not modelled")
    func intPostcode() throws {
        #expect(try Self.decodeRecord(postcode: "40291").login.uuid.isEmpty == false)
    }

    @Test("a String postcode is equally irrelevant")
    func stringPostcode() throws {
        #expect(try Self.decodeRecord(postcode: "\"L2 4EE\"").login.uuid.isEmpty == false)
    }

    @Test("a postcode of an entirely unexpected shape still cannot break decoding")
    func objectPostcode() throws {
        #expect(try Self.decodeRecord(postcode: "{\"a\":1}").name.first == "Nalan")
    }

    @Test("a null id.value is ignored")
    func nullIdentifier() throws {
        #expect(try Self.decodeRecord(idValue: "null").name.last == "Akgul")
    }

    @Test("a present id.value is equally ignored")
    func presentIdentifier() throws {
        #expect(try Self.decodeRecord(idValue: "\"AB-1234\"").name.last == "Akgul")
    }

    // MARK: - The fields we do read

    @Test("the modelled fields all map through")
    func modelledFields() throws {
        let dto = try Self.decodeRecord()
        #expect(dto.login.uuid == "b14f01c5-57dc-4023-be26-fbda38e1fc2d")
        #expect(dto.name.first == "Nalan")
        #expect(dto.location.city == "Van")
        #expect(dto.location.country == "Turkey")
        #expect(dto.email == "nalan@example.com")
        #expect(dto.nat == "TR")
        #expect(dto.picture.large.absoluteString.hasSuffix("women/21.jpg"))
    }

    /// The one payload quirk that genuinely needs handling, because these dates
    /// *are* used: `.iso8601` omits `.withFractionalSeconds` and fails on 60 of
    /// 60 sampled records.
    @Test("fractional-second dates decode")
    func fractionalSecondDates() throws {
        let dto = try Self.decodeRecord(dob: "1945-10-14T19:53:33.877Z")
        let parts = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC")!, from: dto.dob.date)
        #expect(parts.year == 1945)
        #expect(parts.month == 10)
        #expect(parts.day == 14)
    }

    @Test("plain ISO8601 dates still decode via the fallback")
    func plainDates() throws {
        #expect(try Self.decodeRecord(dob: "1992-11-15T17:18:48Z").dob.date.timeIntervalSince1970 > 0)
    }

    @Test("a malformed date is reported, not silently defaulted")
    func malformedDate() {
        #expect(throws: (any Error).self) { try Self.decodeRecord(dob: "not-a-date") }
    }

    @Test("a missing required field fails loudly")
    func missingRequiredField() {
        let json = "{\"results\":[{\"gender\":\"female\"}]}"
        #expect(throws: (any Error).self) {
            try Self.decoder.decode(ProfileListDTO.self, from: Data(json.utf8))
        }
    }
}
