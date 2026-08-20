import Foundation
import SwiftData

/// The SwiftData row backing a `Profile`.
///
/// This type is an implementation detail of the persistence layer and must never
/// escape `SwiftDataProfileStore`: `@Model` classes are reference types bound to a
/// `ModelContext`, so handing one across an actor boundary would both break Swift 6
/// sendability and expose a live, mutable database handle to the UI. Every store
/// method converts to the `Sendable` value type `Profile` before returning.
///
/// Two fields are stored more loosely than their domain counterparts:
/// - `pictureURLString` rather than `URL` — SwiftData persists `URL` fine, but a
///   `String` keeps a malformed or renamed host from failing a whole fetch.
/// - `statusRaw` rather than `DecisionStatus` — a raw `String` means adding or
///   renaming a case never requires a schema migration; the mapper absorbs the
///   change by falling back to `.pending`.
@Model
final class ProfileEntity {

    /// `login.uuid` from the API. Unique so that re-fetching a page updates the
    /// existing row instead of duplicating it — the basis of `upsert`.
    @Attribute(.unique) var uuid: String

    // MARK: - API-owned fields (R-1: written only by the network path)

    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var cell: String
    var gender: String
    var nationalityCode: String
    var dateOfBirth: Date
    var registeredAt: Date
    var city: String
    var state: String
    var country: String

    /// Stored as `String`; see the type doc comment.
    var pictureURLString: String

    /// The page this row arrived on and its offset within that page. Together they
    /// are the only stable ordering the app has — see `SwiftDataProfileStore`.
    var sourcePage: Int
    var indexInPage: Int

    /// Cached portrait bytes.
    ///
    /// Deliberately *without* `@Attribute(.externalStorage)`. The randomuser.me
    /// portraits measure roughly 3.6 KB each and SwiftData only spills a blob to an
    /// external file above ~128 KB, so the attribute would never engage — it would
    /// be inert annotation that implies a file-backed store which does not exist.
    /// Inline storage also keeps the bytes in the same read as the rest of the row,
    /// which is what the list wants.
    var imageData: Data?

    // MARK: - User-owned fields (R-1: written only by user action)

    /// The decision, as a raw `String`; see the type doc comment.
    var statusRaw: String

    /// When the decision was taken; `nil` while the row is pending.
    var decidedAt: Date?

    init(
        uuid: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        cell: String,
        gender: String,
        nationalityCode: String,
        dateOfBirth: Date,
        registeredAt: Date,
        city: String,
        state: String,
        country: String,
        pictureURLString: String,
        sourcePage: Int,
        indexInPage: Int,
        imageData: Data? = nil,
        statusRaw: String = DecisionStatus.pending.rawValue,
        decidedAt: Date? = nil
    ) {
        self.uuid = uuid
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.cell = cell
        self.gender = gender
        self.nationalityCode = nationalityCode
        self.dateOfBirth = dateOfBirth
        self.registeredAt = registeredAt
        self.city = city
        self.state = state
        self.country = country
        self.pictureURLString = pictureURLString
        self.sourcePage = sourcePage
        self.indexInPage = indexInPage
        self.imageData = imageData
        self.statusRaw = statusRaw
        self.decidedAt = decidedAt
    }
}
