import Foundation
import Darwin

/// Samples CPU / memory / network load via mach + BSD APIs and publishes it to
/// `model.stats` on a timer. Rates are computed from deltas between samples.
@MainActor
final class StatsController {
    private let model: NotchViewModel
    private var timer: Timer?

    private var prevCPU: (busy: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, time: Date)?
    private var lastSample = Date.distantPast

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() { setEnabled(model.settings.statsEnabled) }

    /// Starts or stops sampling. Idempotent — driven from the `statsEnabled`
    /// toggle so the mach/BSD sampling loop never runs while stats are off.
    func setEnabled(_ on: Bool) {
        guard on else {
            timer?.invalidate(); timer = nil
            if model.stats != nil { model.stats = nil }
            return
        }
        guard timer == nil else { return }
        sample()
        // Tick every second but only sample once the effective interval has
        // elapsed, so the slider applies live without rescheduling. When the
        // readout isn't on screen we fall back to a slow keep-warm cadence so a
        // freshly-opened page isn't stale, without paying the mach/BSD cost
        // every second while idle.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let interval = self.model.statsVisible
                    ? max(1, self.model.settings.statsRefreshSeconds)
                    : Self.idleInterval
                if Date().timeIntervalSince(self.lastSample) >= interval { self.sample() }
            }
        }
    }

    /// Keep-warm cadence used when no stats readout is visible.
    private static let idleInterval: TimeInterval = 30

    private func sample() {
        lastSample = Date()
        let net = networkRate()
        model.stats = SystemStats(
            cpu: cpuUsage(),
            memoryUsed: memoryUsed(),
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            networkDown: net.down,
            networkUp: net.up
        )
    }

    // MARK: - CPU

    private func cpuUsage() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return model.stats?.cpu ?? 0 }

        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { prevCPU = (busy, total) }

        guard let prev = prevCPU else { return 0 }
        let dBusy = busy &- prev.busy
        let dTotal = total &- prev.total
        return dTotal > 0 ? min(1, Double(dBusy) / Double(dTotal)) : 0
    }

    // MARK: - Memory

    private func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return model.stats?.memoryUsed ?? 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return used * pageSize
    }

    // MARK: - Network

    private func networkRate() -> (down: Double, up: Double) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var ptr = addrs
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            if let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
        }

        let now = Date()
        defer { prevNet = (rx, tx, now) }
        guard let prev = prevNet else { return (0, 0) }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0 else { return (model.stats?.networkDown ?? 0, model.stats?.networkUp ?? 0) }
        return (max(0, Double(rx &- prev.rx) / dt), max(0, Double(tx &- prev.tx) / dt))
    }
}
