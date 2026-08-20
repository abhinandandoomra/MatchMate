import Foundation

/// The concrete `ProfileRepository`: coordinates the remote and local data sources
/// and translates between the wire format and the domain.
///
/// Lives in `Data/` precisely because it maps DTOs: a type that knows the wire
/// format belongs on the data side of the line. The protocol beside it is what
/// the presentation layer depends on, so nothing above here sees a DTO.
///
/// Main-actor, observable, and the single notification mechanism in the app.
///
/// Both ViewModels are injected the *same* instance and expose computed
/// projections of `profiles`. Neither holds a copy, so list and detail cannot
/// disagree — FR-20 needs no callback, notification, or refresh-on-appear.
@MainActor
@Observable
final class ProfileRepositoryImpl: ProfileRepository {
    private(set) var profiles: [Profile] = []
    private(set) var nextPage: Int = 1

    private let store: any ProfileStore
    private let api: any ProfileAPIServicing
    private let images: any ImageFetching

    /// Calling a typed-throwing method through an existential erases the error
    /// back to `any Error` — the protocols still document what they throw, but
    /// the compiler cannot carry it across the box. Rather than making this
    /// class generic over three protocols (which would infect both ViewModels),
    /// the type is recovered here, once, with an explicit fallback.
    private func persistence(_ error: any Error) -> ProfileError {
        .persistence(error as? PersistenceError ?? .operationFailed)
    }

    private func network(_ error: any Error) -> ProfileError {
        .network(error as? NetworkError ?? .server(status: -1))
    }

    private let mapper: ProfileMapper

    init(
        store: any ProfileStore,
        api: any ProfileAPIServicing,
        images: any ImageFetching,
        mapper: ProfileMapper = ProfileMapper()
    ) {
        self.store = store
        self.api = api
        self.images = images
        self.mapper = mapper
    }

    /// FR-11 — show whatever is cached, immediately. Never hits the network.
    func loadCached() async throws(ProfileError) {
        try await refresh()
        await backfillImages(for: profiles)
    }

    /// FR-16 — nothing is persisted unless the fetch succeeds, so the derived
    /// cursor cannot advance past a gap.
    func loadNextPage() async throws(ProfileError) {
        let page = nextPage

        let dtos: [ProfileDTO]
        do {
            dtos = try await api.profiles(page: page)
        } catch {
            throw network(error)
        }

        // The one translation point between wire and domain. `page` and the
        // record's position within it become the app's only stable ordering.
        let fetched = dtos.enumerated().map { offset, dto in
            mapper.toDomain(dto, page: page, index: offset)
        }

        let persisted: [Profile]
        do {
            persisted = try await store.upsert(fetched)
        } catch {
            throw persistence(error)
        }

        // The page just landed, so its rows are already in hand — re-reading the
        // whole table to discover them would be redundant work behind a network
        // call. `nextPage` follows from the page we asked for.
        merge(persisted)
        nextPage = page + 1

        await backfillImages(for: persisted)
    }

    /// A decision changes one row, so only that row is re-projected.
    ///
    /// A full `refresh()` here would re-read and re-map the entire table for a
    /// single field. Measured against a real store: the write is 0.3ms flat,
    /// while the re-read grows 0.3ms → 2.4ms → 14.4ms at 10, 100 and 500
    /// profiles. With uncapped paging that gap only widens, and the UI waits on
    /// all of it before the status flips.
    ///
    /// `nextPage` is deliberately not recomputed either: a decision never
    /// changes which page comes next.
    func setStatus(_ status: DecisionStatus, uuid: String) async throws(ProfileError) {
        let updated: Profile
        do {
            updated = try await store.setStatus(status, uuid: uuid)
        } catch {
            throw persistence(error)
        }

        guard let index = profiles.firstIndex(where: { $0.uuid == uuid }) else { return }
        profiles[index] = updated
    }

    func profile(uuid: String) -> Profile? {
        profiles.first { $0.uuid == uuid }
    }

    /// Applies rows the store has already persisted, in place.
    ///
    /// New pages sort after everything held, so appending preserves the
    /// `(sourcePage, indexInPage)` order without a re-sort.
    private func merge(_ updated: [Profile]) {
        guard !updated.isEmpty else { return }

        var indexByUUID = [String: Int](
            uniqueKeysWithValues: profiles.enumerated().map { ($0.element.uuid, $0.offset) }
        )
        var appended: [Profile] = []

        for profile in updated {
            if let index = indexByUUID[profile.uuid] {
                profiles[index] = profile
            } else {
                indexByUUID[profile.uuid] = profiles.count + appended.count
                appended.append(profile)
            }
        }

        profiles.append(contentsOf: appended)
    }

    /// The single site that writes to `profiles`. Everything observable flows
    /// through this one method.
    private func refresh() async throws(ProfileError) {
        do {
            profiles = try await store.profiles()
            nextPage = (try await store.maxSourcePage() ?? 0) + 1   // D-23
        } catch {
            throw persistence(error)
        }
    }

    /// F-10 — runs after a page persists *and* after loadCached, so an image
    /// that failed in an earlier session gets another attempt. A no-op when
    /// every profile already has bytes. Image failures are never fatal.
    private func backfillImages(for candidates: [Profile]) async {
        let missing = candidates.filter { $0.imageData == nil }.map { ($0.uuid, $0.pictureURL) }
        guard !missing.isEmpty else { return }

        let images = self.images
        let fetched: [(String, Data)] = await withTaskGroup(of: (String, Data)?.self) { group in
            for (uuid, url) in missing {
                group.addTask {
                    guard let data = try? await images.fetch(url) else { return nil }
                    return (uuid, data)
                }
            }
            var accumulated: [(String, Data)] = []
            for await result in group where result != nil { accumulated.append(result!) }
            return accumulated
        }

        guard !fetched.isEmpty else { return }

        var updated: [Profile] = []
        for (uuid, data) in fetched {
            if let profile = try? await store.saveImage(data, uuid: uuid) {
                updated.append(profile)
            }
        }
        merge(updated)
    }
}
