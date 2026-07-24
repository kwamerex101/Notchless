import Foundation
import Network
import SystemConfiguration

/// The Mac's internet connectivity, distinguishing "no link" from "link up but
/// no route to the internet" (captive portal, router with no WAN, etc.).
enum NetworkConnectivity: Equatable {
    case online
    case noInternet
    case offline
}

/// Reports internet reachability changes (for the "No Internet" / "Back online"
/// notch banners).
@MainActor
final class NetworkService {
    /// Called on every connectivity transition after the first snapshot.
    var onChange: ((NetworkConnectivity) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rexdanquah.Notchless.network")
    private var lastConnectivity: NetworkConnectivity?

    func start() {
        // Created once on the main actor and captured by value below — CFType
        // reads are thread-safe, so the path-update handler (which runs on
        // `queue`, not main) can use it without touching `self`.
        let reachability = Self.makeReachability()

        monitor.pathUpdateHandler = { [weak self] path in
            let connectivity: NetworkConnectivity
            if path.status == .satisfied {
                connectivity = Self.hasInternet(reachability) ? .online : .noInternet
            } else {
                connectivity = .offline
            }
            Task { @MainActor in
                guard let self, self.lastConnectivity != connectivity else { return }
                let hadPrevious = self.lastConnectivity != nil
                self.lastConnectivity = connectivity
                if hadPrevious { self.onChange?(connectivity) }   // skip the first snapshot
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated private static func makeReachability() -> SCNetworkReachability? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }
    }

    /// True when the link has a route to the internet, not merely a link-local
    /// connection (e.g. Wi-Fi joined but no DHCP/gateway, or a captive portal).
    nonisolated private static func hasInternet(_ reachability: SCNetworkReachability?) -> Bool {
        guard let reachability else { return true }   // fail open: don't guess on API failure
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else { return true }
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }
}
