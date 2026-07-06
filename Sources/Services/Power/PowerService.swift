import IOKit.ps
import Foundation

struct PowerState: Equatable {
    var isCharging: Bool
    var percent: Int
}

/// Watches battery charge/charging state via IOKit power sources and reports
/// transitions (plugged in, unplugged, low battery). See PLAN.md Phase 8.
@MainActor
final class PowerService {
    var onChange: ((PowerState, _ previous: PowerState?) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var last: PowerState?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<PowerService>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { service.emit() }
        }, context)?.takeRetainedValue() else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        last = read()
    }

    private func emit() {
        guard let state = read() else { return }
        let previous = last
        if state != previous {
            onChange?(state, previous)
            last = state
        }
    }

    private func read() -> PowerState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let charging = state == kIOPSACPowerValue
            let percent = max > 0 ? Int((Double(current) / Double(max)) * 100) : current
            return PowerState(isCharging: charging, percent: percent)
        }
        return nil
    }
}
