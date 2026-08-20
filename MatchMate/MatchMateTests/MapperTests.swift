import Foundation
import Testing
@testable import MatchMate

struct MapperTests {

    @Test("row shows full name and initials")
    func rowIdentity() {
        let row = MatchRowMapper.map(.fixture(firstName: "Nalan", lastName: "Akgul"))
        #expect(row.fullName == "Nalan Akgul")
        #expect(row.initials == "NA")
    }

    @Test("age is computed from date of birth")
    func age() {
        let born = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 1990, month: 1, day: 1))!
        let now = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let row = MatchRowMapper.map(.fixture(dateOfBirth: born), now: now)
        #expect(row.subtitle.contains("36"))
    }

    /// The row localises the country from the ISO code rather than echoing the
    /// API's English string, so "TR" renders as "Türkiye" on a current runtime.
    @Test("subtitle carries city and the localised country")
    func subtitleLocation() {
        let row = MatchRowMapper.map(.fixture(nationalityCode: "TR", city: "Van", country: "Turkey"))
        let expectedCountry = Locale.current.localizedString(forRegionCode: "TR") ?? "TR"
        #expect(row.subtitle.contains("Van"))
        #expect(row.subtitle.contains(expectedCountry))
    }

    @Test("status passes through to the row")
    func status() {
        #expect(MatchRowMapper.map(.fixture(status: .accepted)).decision?.title == "Accepted")
    }

    @Test("detail maps a full country name from the ISO code — TD-09")
    func detailCountryName() {
        let detail = ProfileDetailMapper.map(.fixture(nationalityCode: "TR"))
        let rendered = detail.sections.flatMap(\.fields).map(\.value).joined(separator: " ")
        #expect(rendered.contains("Turkey") || rendered.contains("TR"))
    }

    @Test("detail carries the person's name")
    func detailIdentity() {
        let detail = ProfileDetailMapper.map(.fixture(firstName: "Nalan", lastName: "Akgul"))
        #expect(detail.fullName == "Nalan Akgul")
    }
}
