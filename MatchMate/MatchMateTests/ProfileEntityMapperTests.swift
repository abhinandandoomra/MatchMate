import Foundation
import Testing
import SwiftData
@testable import MatchMate

/// R-1 — the single most important invariant in the codebase: the network path
/// must never overwrite a decision the user made.
@MainActor
struct ProfileEntityMapperTests {

    private func makeEntity(status: DecisionStatus, decidedAt: Date?) -> ProfileEntity {
        let entity = ProfileEntityMapper().makeEntity(from: .fixture(uuid: "u1"))
        entity.statusRaw = status.rawValue
        entity.decidedAt = decidedAt
        return entity
    }

    @Test("a sync cannot clobber an accepted decision")
    func syncPreservesAccepted() {
        let decidedAt = Date(timeIntervalSince1970: 1000)
        let entity = makeEntity(status: .accepted, decidedAt: decidedAt)

        // The API always reports .pending — it has no concept of a decision.
        ProfileEntityMapper().applyAPIFields(.fixture(uuid: "u1", status: .pending), to: entity)

        #expect(entity.statusRaw == DecisionStatus.accepted.rawValue)
        #expect(entity.decidedAt == decidedAt)
    }

    @Test("a sync cannot clobber a declined decision")
    func syncPreservesDeclined() {
        let entity = makeEntity(status: .declined, decidedAt: Date(timeIntervalSince1970: 5))
        ProfileEntityMapper().applyAPIFields(.fixture(uuid: "u1", status: .pending), to: entity)
        #expect(entity.statusRaw == DecisionStatus.declined.rawValue)
    }

    @Test("a sync does refresh API-owned fields")
    func syncUpdatesAPIFields() {
        let entity = makeEntity(status: .accepted, decidedAt: nil)
        let updated = Profile.fixture(uuid: "u1", firstName: "Changed", lastName: "Name",
                                      sourcePage: 4, indexInPage: 2, status: .pending)
        ProfileEntityMapper().applyAPIFields(updated, to: entity)

        #expect(entity.firstName == "Changed")
        #expect(entity.sourcePage == 4)
        #expect(entity.indexInPage == 2)
        #expect(entity.statusRaw == DecisionStatus.accepted.rawValue)   // still untouched
    }

    @Test("a sync cannot erase cached portrait bytes")
    func syncPreservesImageData() {
        let entity = makeEntity(status: .pending, decidedAt: nil)
        entity.imageData = Data([1, 2, 3])

        // API-decoded profiles always carry imageData == nil.
        ProfileEntityMapper().applyAPIFields(.fixture(uuid: "u1", imageData: nil), to: entity)

        #expect(entity.imageData == Data([1, 2, 3]))
    }

    @Test("round-trips to domain")
    func roundTrip() {
        let entity = ProfileEntityMapper().makeEntity(from: .fixture(uuid: "u9", status: .declined))
        let domain = ProfileEntityMapper().toDomain(entity)
        #expect(domain.uuid == "u9")
        #expect(domain.status == .declined)
    }

    @Test("an unknown stored status degrades to pending rather than crashing")
    func unknownStatus() {
        let entity = ProfileEntityMapper().makeEntity(from: .fixture())
        entity.statusRaw = "something-from-a-future-version"
        #expect(ProfileEntityMapper().toDomain(entity).status == .pending)
    }
}
