import Foundation
import Network
import Synchronization

/// `NWPathMonitor` wrapped in the `ConnectivityMonitoring` seam.
///
/// Intentionally logic-free — it reports reachability and nothing else. Every
/// decision about what to do when connectivity changes lives in the repository
/// and ViewModels, which is why this type is excluded from the coverage target.
///
/// `Sendable` comes from a `Mutex` rather than an actor: `pathUpdateHandler` is
/// a synchronous callback, and hopping to an actor from it would let two path
/// updates land out of order.
final class NetworkMonitor: ConnectivityMonitoring, Sendable {
    private struct State {
        var isOnline: Bool
        var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.matchmate.network-monitor")
    private let state: Mutex<State>

    init() {
        state = Mutex(State(isOnline: monitor.currentPath.status == .satisfied))

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        state.withLock { current in
            for subscriber in current.subscribers.values { subscriber.finish() }
            current.subscribers.removeAll()
        }
    }

    var isOnline: Bool {
        get async { state.withLock { $0.isOnline } }
    }

    /// Yields the current value on subscription so a consumer never has to wait
    /// for a change to learn where it stands, then one value per transition.
    func stream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            let current = state.withLock { current -> Bool in
                current.subscribers[id] = continuation
                return current.isOnline
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { current in _ = current.subscribers.removeValue(forKey: id) }
            }
        }
    }

    /// `NWPathMonitor` fires on any path change — a Wi-Fi to cellular handover
    /// included — so unchanged reachability is swallowed to keep the stream a
    /// stream of transitions.
    private func handle(_ isOnline: Bool) {
        let subscribers = state.withLock { current -> [AsyncStream<Bool>.Continuation] in
            guard current.isOnline != isOnline else { return [] }
            current.isOnline = isOnline
            return Array(current.subscribers.values)
        }
        for subscriber in subscribers { subscriber.yield(isOnline) }
    }
}
