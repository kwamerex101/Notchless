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
    /// Pending confirmation of a `.noInternet` classification. A path that is
    /// `.satisfied` but has no route is the normal state for a brief moment
    /// during a reconnect, so we hold the banner for `noInternetDebounce`
    /// before committing it. Any new path event cancels it.
    private var debounceTask: Task<Void, Never>?
    private let noInternetDebounce: Duration = .milliseconds(1500)

    func start() {
        // Created once on the main actor and captured by value below — CFType
        // reads are thread-safe, so the path-update handler (which runs on
        // `queue`, not main) can use it without touching `self`.
        let reachability = Self.makeReachability()

        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePath(satisfied: satisfied, reachability: reachability)
            }
        }
        monitor.start(queue: queue)
    }

    /// Classifies one path update. `.offline` and `.online` commit
    /// immediately; `.noInternet` is deferred (see `debounceTask`) so a normal
    /// reconnect — where `NWPath` flips to `.satisfied` a tick before the route
    /// resolves — doesn't post a transient "No Internet" then "Back online".
    private func handlePath(satisfied: Bool, reachability: SCNetworkReachability?) {
        // Any fresh path event supersedes a pending "no internet" confirmation.
        debounceTask?.cancel()
        debounceTask = nil

        guard satisfied else {
            commit(.offline)
            return
        }
        if Self.hasInternet(reachability) {
            commit(.online)
            return
        }
        // Path is up but there's no route yet. Wait, then re-check: if the
        // route resolved within the window it was just reconnect lag → go
        // straight to `.online` with no banner; otherwise it's really down.
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.noInternetDebounce ?? .milliseconds(1500))
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.commit(Self.hasInternet(reachability) ? .online : .noInternet)
        }
    }

    /// Applies a settled classification, emitting only real transitions and
    /// swallowing the very first snapshot (so launch never fires a banner).
    private func commit(_ connectivity: NetworkConnectivity) {
        guard lastConnectivity != connectivity else { return }
        let hadPrevious = lastConnectivity != nil
        lastConnectivity = connectivity
        if hadPrevious { onChange?(connectivity) }
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
