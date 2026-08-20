import Foundation
import SwiftData

/// Provisioning a SwiftData stack, independent of what is being stored.
///
/// Container creation is the one genuinely generic part of persistence:
/// assembling a schema, choosing on-disk or in-memory, and turning SwiftData's
/// untyped throw into the app's error vocabulary. Everything *else* about
/// persistence is specific to what is being stored, and lives with its feature.
protocol ModelContainerProviding: Sendable {
    func container() throws(PersistenceError) -> ModelContainer
}

struct SwiftDataContainerProvider: ModelContainerProviding {
    private let schema: Schema
    private let isStoredInMemoryOnly: Bool

    /// - Parameter isStoredInMemoryOnly: when `true` the store lives entirely in
    ///   memory and never touches disk — how the test suite runs, so a suite
    ///   exercises this same provisioning path rather than a parallel one that
    ///   could drift from production.
    init(schema: Schema, isStoredInMemoryOnly: Bool = false) {
        self.schema = schema
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }

    func container() throws(PersistenceError) -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A corrupt or migration-incompatible store, or no room on disk.
            throw PersistenceError.unavailable
        }
    }
}
