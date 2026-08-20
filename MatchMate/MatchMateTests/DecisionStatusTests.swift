import Testing
@testable import MatchMate

/// Views emit intent; the ViewModel is the only place intent becomes domain
/// state. This is that translation.
@MainActor
struct DecisionIntentTests {

    @Test("accept and decline map to their statuses")
    func decisions() {
        #expect(MatchListViewModel.status(for: .accept) == .accepted)
        #expect(MatchListViewModel.status(for: .decline) == .declined)
    }

    @Test("undo returns a profile to undecided")
    func undo() {
        #expect(MatchListViewModel.status(for: .undo) == .pending)
    }
}

struct DecisionStatusTests {

    @Test("isDecided reflects the three states")
    func decided() {
        #expect(DecisionStatus.pending.isDecided == false)
        #expect(DecisionStatus.accepted.isDecided)
        #expect(DecisionStatus.declined.isDecided)
    }

    @Test("the raw value round-trips, since it is what the store persists")
    func rawValues() {
        for status in DecisionStatus.allCases {
            #expect(DecisionStatus(rawValue: status.rawValue) == status)
        }
    }
}
