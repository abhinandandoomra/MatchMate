import Foundation

struct Profile: Sendable, Identifiable, Equatable {
    var id: String { uuid }

    // API-owned — R-1: written only by the network path
    let uuid: String
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let cell: String
    let gender: String
    let nationalityCode: String
    let dateOfBirth: Date
    let registeredAt: Date
    let city: String
    let state: String
    let country: String
    let pictureURL: URL
    let sourcePage: Int
    let indexInPage: Int

    // API-owned cache of the portrait bytes (D-07)
    var imageData: Data?

    // User-owned — R-1: written only by user action
    var status: DecisionStatus
    var decidedAt: Date?

    var fullName: String { "\(firstName) \(lastName)" }
}
