import Foundation
import IOKit.ps

/// Reads the Mac's power source via IOKit and publishes it to `model.battery`,
/// updating on every power-source change (plug/unplug, charge tick).
@MainActor
final class BatteryController {
    private let model: NotchViewModel
    private var runLoopSource: CFRunLoopSource?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let controller = Unmanaged<BatteryController>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in controller.refresh() }
        }, context)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = source
        }
    }

    private func refresh() {
        model.battery = Self.read()
    }

    /// Returns nil on Macs without a battery (desktops).
    static func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1

            return BatteryInfo(
                level: level,
                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: state == kIOPSACPowerValue,
                isCharged: desc[kIOPSIsChargedKey] as? Bool ?? false,
                timeRemaining: toEmpty > 0 ? toEmpty : nil,
                timeToFull: toFull > 0 ? toFull : nil
            )
        }
        return nil
    }
}
