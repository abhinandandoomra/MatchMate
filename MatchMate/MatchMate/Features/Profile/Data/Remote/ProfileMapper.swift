import Foundation

/// The single translation point between the wire format and the domain.
///
/// Stateless and synchronous: no I/O, no clock, so a mapping is exhaustively
/// testable from a fixture. Held as a value the repository owns rather than a
/// free-floating namespace, so it can be substituted if the wire shape ever
/// needs a second interpretation.
struct ProfileMapper: Sendable {

    /// - Parameters:
    ///   - page: the page the record arrived on.
    ///   - index: its position within that page. Together these are the app's
    ///     only stable ordering, since the API defines no sort of its own.
    func toDomain(_ dto: ProfileDTO, page: Int, index: Int) -> Profile {
        Profile(
            uuid: dto.login.uuid,
            firstName: dto.name.first,
            lastName: dto.name.last,
            email: dto.email,
            phone: dto.phone,
            cell: dto.cell,
            gender: dto.gender,
            nationalityCode: dto.nat,
            dateOfBirth: dto.dob.date,
            registeredAt: dto.registered.date,
            city: dto.location.city,
            state: dto.location.state,
            country: dto.location.country,
            pictureURL: dto.picture.large,
            sourcePage: page,
            indexInPage: index,
            // R-1 — the network path never invents user state. Portrait bytes are
            // backfilled separately, and a decision is only ever set by a tap.
            imageData: nil,
            status: .pending,
            decidedAt: nil
        )
    }
}
