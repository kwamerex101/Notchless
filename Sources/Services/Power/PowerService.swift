import IOKit.ps
import Foundation

struct PowerState: Equatable {
    var isCharging: Bool
    var percent: Int
    /// Minutes until fully charged, or nil while IOKit is still calculating the
    /// estimate (kIOPSTimeToFullChargeKey reports -1) or when unavailable.
    var timeToFullMinutes: Int?
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
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            // IOKit reports -1 while still calculating, and can transiently
            // report absurd minute counts (e.g. 1092) right after plug-in.
            // Only trust a plausible estimate (under 24h); anything else is
            // treated as "calculating" (nil → device-name-only subtitle).
            let plausibleToFull = (0 < toFull && toFull < 1440) ? toFull : nil
            return PowerState(isCharging: charging, percent: percent,
                               timeToFullMinutes: plausibleToFull)
        }
        return nil
    }

    /// The Mac's configured computer name (e.g. "Rex's MacBook Pro"), used as the
    /// device label in the charging banner. There's no public API for the bare
    /// marketing model name ("MacBook Pro") short of parsing `system_profiler`, so
    /// this reuses the stable, already-available host name instead.
    static var deviceName: String {
        Host.current().localizedName ?? "This Mac"
    }

    /// Formats minutes as `h:mm` (e.g. 134 → "2:14").
    static func formatTimeToFull(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
