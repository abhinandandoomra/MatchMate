import Foundation
import Testing
import SwiftData
@testable import MatchMate

struct ModelContainerProvidingTests {

    /// Proves the seam is real: the store can be built on any provider, not
    /// just the SwiftData one.
    struct FailingProvider: ModelContainerProviding {
        func container() throws(PersistenceError) -> ModelContainer { throw .unavailable }
    }

    @Test("an in-memory container provisions from the store's schema")
    func inMemoryProvisions() throws {
        let container = try SwiftDataContainerProvider(
            schema: Schema([ProfileEntity.self]),
            isStoredInMemoryOnly: true
        ).container()
        #expect(container.schema.entities.isEmpty == false)
    }

    @Test("the schema contains the profile entity")
    func schemaContents() {
        let names = Schema([ProfileEntity.self]).entities.map(\.name)
        #expect(names.contains("ProfileEntity"))
    }

    @Test("a provisioning failure surfaces as .unavailable, not a crash")
    func failurePropagates() {
        #expect(throws: PersistenceError.unavailable) {
            _ = try SwiftDataProfileStore(provider: FailingProvider())
        }
    }

    @Test("a store built with the default provider is usable")
    func storeIsUsable() async throws {
        let store = try SwiftDataProfileStore(isStoredInMemoryOnly: true)
        try await store.upsert([.fixture(uuid: "a")])
        #expect(try await store.profiles().count == 1)
    }

    /// The in-memory flag is what keeps the suite off disk, so it is worth
    /// pinning that two stores really are isolated from one another.
    @Test("in-memory stores do not share state")
    func inMemoryStoresAreIsolated() async throws {
        let first = try SwiftDataProfileStore(isStoredInMemoryOnly: true)
        let second = try SwiftDataProfileStore(isStoredInMemoryOnly: true)

        try await first.upsert([.fixture(uuid: "a")])

        #expect(try await first.profiles().count == 1)
        #expect(try await second.isEmpty())
    }
}
