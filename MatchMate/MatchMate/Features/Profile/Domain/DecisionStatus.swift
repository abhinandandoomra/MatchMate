import Foundation

enum DecisionStatus: String, Codable, Sendable, CaseIterable {
    case pending, accepted, declined

    var isDecided: Bool { self != .pending }

}
