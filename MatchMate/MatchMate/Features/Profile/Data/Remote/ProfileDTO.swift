import Foundation

/// The envelope randomuser.me wraps every response in. The sibling `info`
/// object is not declared: the page identity the app cares about is the request
/// triple (seed, results, page), not the echo the server sends back.
struct ProfileListDTO: Decodable, Sendable, Equatable {
    let results: [ProfileDTO]
}

/// One record from `results`. Only the fields the domain needs are declared;
/// `Decodable` ignores everything else in the payload — street, coordinates,
/// timezone, postcode, `id`, `name.title` — so upstream additions cannot break
/// decoding, and inconsistently-typed fields we never read cannot either.
struct ProfileDTO: Decodable, Sendable, Equatable {
    let gender: String
    let name: NameDTO
    let location: LocationDTO
    let email: String
    let login: LoginDTO
    let dob: DateInfoDTO
    let registered: DateInfoDTO
    let phone: String
    let cell: String
    let picture: PictureDTO
    let nat: String
}
//
// Only the fields the domain actually consumes are declared. `Decodable`
// ignores every other key in the payload, which is not just tidiness — it is
// what makes two of this API's quirks irrelevant rather than handled:
//
//   • `location.postcode` is an `Int` on some records and a `String` on others.
//   • `id.value` is `null` on roughly one record in four.
//
// Both would need custom decoding if declared. Neither reaches the domain, so
// neither is declared, and no decoding strategy is needed for them at all.

struct NameDTO: Decodable, Sendable, Equatable {
    let first: String
    let last: String
}

struct LoginDTO: Decodable, Sendable, Equatable {
    /// The app's primary key everywhere downstream (`ProfileStore` is keyed by it).
    let uuid: String
}

struct LocationDTO: Decodable, Sendable, Equatable {
    let city: String
    let state: String
    let country: String
}

struct PictureDTO: Decodable, Sendable, Equatable {
    /// The only size the UI uses; `medium`/`thumbnail` are deliberately dropped.
    let large: URL
}

struct DateInfoDTO: Decodable, Sendable, Equatable {
    /// `"1945-10-14T19:53:33.877Z"` — the one payload quirk that *is* handled,
    /// because these dates are used. `.iso8601` omits `.withFractionalSeconds`
    /// and fails on every record; see `DateDecoding.swift`.
    ///
    /// The sibling `age` is deliberately not decoded: age is derived from this
    /// date with an injectable `now`, so it stays deterministic under test.
    let date: Date
}
