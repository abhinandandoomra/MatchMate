import Foundation
import Observation

@MainActor
@Observable
final class ProfileDetailViewModel {

    private let repo: any ProfileRepository
    private let uuid: String
    private var isWriting = false

    init(repo: any ProfileRepository, uuid: String) {
        self.repo = repo
        self.uuid = uuid
    }

    /// COMPUTED, never stored.
    ///
    /// This is what makes list and detail agree with zero synchronisation code:
    /// detail holds no copy of the profile, only a `uuid` and a reference to the
    /// same `ProfileRepository` the list uses. A decision made on either screen
    /// mutates `repo.profiles`, and Observation re-reads this property on both.
    /// Storing the mapped model here would reintroduce exactly the two-copies
    /// problem the shared repository exists to avoid.
    var profile: ProfileDetailUIModel? {
        repo.profile(uuid: uuid).map { ProfileDetailMapper.map($0, isBusy: isWriting) }
    }

    /// The row was evicted (or never cached) — the view shows a not-found state.
    var isMissing: Bool { profile == nil }

    /// Same in-flight guard as the list — see `MatchListViewModel.setStatus`.
    func apply(_ intent: DecisionIntent) async {
        guard !isWriting else { return }
        guard repo.profile(uuid: uuid) != nil else { return }

        isWriting = true
        defer { isWriting = false }

        try? await repo.setStatus(MatchListViewModel.status(for: intent), uuid: uuid)
    }
}
