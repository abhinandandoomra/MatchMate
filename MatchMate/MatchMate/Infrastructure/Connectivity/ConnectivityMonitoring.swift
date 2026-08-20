import Foundation

protocol ConnectivityMonitoring: Sendable {
    var isOnline: Bool { get async }
    func stream() -> AsyncStream<Bool>
}
