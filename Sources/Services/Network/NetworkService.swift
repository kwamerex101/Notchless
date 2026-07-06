import Foundation
import Network

/// Reports internet reachability changes (for the "No Internet" / "Back online"
/// notch banners).
@MainActor
final class NetworkService {
    /// Called with `true` when connectivity is restored, `false` when lost.
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rexdanquah.Notchless.network")
    private var lastConnected: Bool?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.lastConnected != connected else { return }
                let hadPrevious = self.lastConnected != nil
                self.lastConnected = connected
                if hadPrevious { self.onChange?(connected) }   // skip the first snapshot
            }
        }
        monitor.start(queue: queue)
    }
}
