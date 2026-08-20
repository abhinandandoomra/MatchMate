import Foundation
import Observation

/// What the presentation layer is allowed to know about profile data.
///
/// Speaks only in domain values — a `ProfileDTO` never appears here, so the
/// wire format stays an implementation detail of `Data/Remote`.
///
/// The `Observable` constraint is load-bearing, not decoration. Both ViewModels
/// expose *computed* projections of `profiles`, and SwiftUI re-renders them
/// because reading through this protocol still trips the observation registrar
/// on the conforming type. Requiring `Observable` is what makes that a compiler
/// guarantee rather than a convention a future conformer could quietly break —
/// and it is the whole of the list/detail consistency mechanism.
@MainActor
protocol ProfileRepository: AnyObject, Observable {

    /// The single source of truth the UI projects from.
    var profiles: [Profile] { get }

    /// Derived from the persisted rows, never stored separately.
    var nextPage: Int { get }

    /// Show whatever is cached. Never hits the network.
    func loadCached() async throws(ProfileError)

    /// Fetch, map and persist the next page. Nothing is written unless the
    /// fetch succeeds, so the cursor cannot advance past a gap.
    func loadNextPage() async throws(ProfileError)

    func setStatus(_ status: DecisionStatus, uuid: String) async throws(ProfileError)

    func profile(uuid: String) -> Profile?
}
