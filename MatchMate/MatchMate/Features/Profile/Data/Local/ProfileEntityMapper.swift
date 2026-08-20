import Foundation
import SwiftData

/// Translates between the SwiftData row and the `Sendable` domain value.
///
/// The direction matters more than the mechanics: `toDomain` is total (it can never
/// fail, so a single bad row cannot blank the list), while the write direction is
/// deliberately *partial* — see `applyAPIFields`.
struct ProfileEntityMapper: Sendable {

    /// A syntactically valid URL that resolves to nothing. Used when a stored string
    /// somehow fails to parse, so that one corrupt row degrades to a missing portrait
    /// rather than an optional that every call site downstream has to unwrap.
    private let placeholderPictureURL = URL(string: "about:blank")!

    // MARK: - Read

    /// Row to value. Never throws and never returns `nil`: both loosely typed
    /// columns (`statusRaw`, `pictureURLString`) fall back rather than fail, which is
    /// the whole reason they are stored loosely.
    func toDomain(_ entity: ProfileEntity) -> Profile {
        Profile(
            uuid: entity.uuid,
            firstName: entity.firstName,
            lastName: entity.lastName,
            email: entity.email,
            phone: entity.phone,
            cell: entity.cell,
            gender: entity.gender,
            nationalityCode: entity.nationalityCode,
            dateOfBirth: entity.dateOfBirth,
            registeredAt: entity.registeredAt,
            city: entity.city,
            state: entity.state,
            country: entity.country,
            pictureURL: URL(string: entity.pictureURLString) ?? placeholderPictureURL,
            sourcePage: entity.sourcePage,
            indexInPage: entity.indexInPage,
            imageData: entity.imageData,
            // An unrecognised raw value (a case removed in a later build, a hand-edited
            // store) reads as `.pending` rather than crashing.
            status: DecisionStatus(rawValue: entity.statusRaw) ?? .pending,
            decidedAt: entity.decidedAt
        )
    }

    // MARK: - Write

    /// Updates an existing row with freshly fetched API data.
    ///
    /// **R-1 — the network can never clobber a user's Accept/Decline decision.**
    ///
    /// This function assigns API-owned fields *only*. It does not assign `statusRaw`
    /// and it does not assign `decidedAt`, and the absence of those two assignments
    /// **is** the invariant — there is no guard, no flag and no branch enforcing R-1
    /// anywhere else in the app. `upsert` re-runs on every refresh with profiles
    /// decoded straight from the API, where `status` is always `.pending`; adding
    /// either line here would reset every decision the user has ever made, on the
    /// next successful page load, silently.
    ///
    /// Do not "complete" this mapping. `setStatus(_:uuid:)` is the only writer of
    /// those two columns.
    func applyAPIFields(_ profile: Profile, to entity: ProfileEntity) {
        // `uuid` is intentionally not reassigned: it is the identity the row was
        // located by, and it is what makes this an update rather than an insert.
        entity.firstName = profile.firstName
        entity.lastName = profile.lastName
        entity.email = profile.email
        entity.phone = profile.phone
        entity.cell = profile.cell
        entity.gender = profile.gender
        entity.nationalityCode = profile.nationalityCode
        entity.dateOfBirth = profile.dateOfBirth
        entity.registeredAt = profile.registeredAt
        entity.city = profile.city
        entity.state = profile.state
        entity.country = profile.country
        entity.pictureURLString = profile.pictureURL.absoluteString
        entity.sourcePage = profile.sourcePage
        entity.indexInPage = profile.indexInPage

        // Portrait bytes are API-owned but *accumulated*, not delivered with the page:
        // a profile decoded from JSON always carries `imageData == nil`. Assigning it
        // unconditionally would throw away the cached portrait on every refresh and
        // force the backfill to re-download it, so only real bytes overwrite.
        if let imageData = profile.imageData {
            entity.imageData = imageData
        }

        // No `entity.statusRaw = ...` and no `entity.decidedAt = ...`. See R-1 above.
    }

    /// Value to row, for a `uuid` that has never been seen before.
    ///
    /// Unlike `applyAPIFields`, this *does* seed `statusRaw` and `decidedAt` from the
    /// profile: a brand-new row has no prior decision to protect, so there is nothing
    /// R-1 could clobber. In the normal insert path the profile comes from the API
    /// and both values are simply the `.pending` defaults.
    func makeEntity(from profile: Profile) -> ProfileEntity {
        ProfileEntity(
            uuid: profile.uuid,
            firstName: profile.firstName,
            lastName: profile.lastName,
            email: profile.email,
            phone: profile.phone,
            cell: profile.cell,
            gender: profile.gender,
            nationalityCode: profile.nationalityCode,
            dateOfBirth: profile.dateOfBirth,
            registeredAt: profile.registeredAt,
            city: profile.city,
            state: profile.state,
            country: profile.country,
            pictureURLString: profile.pictureURL.absoluteString,
            sourcePage: profile.sourcePage,
            indexInPage: profile.indexInPage,
            imageData: profile.imageData,
            statusRaw: profile.status.rawValue,
            decidedAt: profile.decidedAt
        )
    }
}
