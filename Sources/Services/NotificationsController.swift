import SwiftUI

/// Turns system events (battery, Bluetooth, Focus) into transient notch
/// notifications, gated by the per-category settings toggles.
@MainActor
final class NotificationsController {
    private let model: NotchViewModel
    private let power = PowerService()
    private let bluetooth = BluetoothService()
    private let focus = FocusService()

    private var settings: SettingsStore { model.settings }

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        power.onChange = { [weak self] state, previous in
            guard let self, self.settings.batteryEnabled else { return }
            guard let previous else { return } // skip first snapshot
            if state.isCharging != previous.isCharging {
                self.model.show(TransientNotification(
                    systemImage: state.isCharging ? "battery.100.bolt" : "battery.50",
                    tint: state.isCharging ? .green : .white,
                    title: state.isCharging ? "Charging" : "On Battery",
                    subtitle: nil,
                    trailingText: "\(state.percent)%"
                ))
            } else if !state.isCharging, state.percent <= 20, previous.percent > 20 {
                self.model.show(TransientNotification(
                    systemImage: "battery.25",
                    tint: .red,
                    title: "Low Battery",
                    subtitle: "\(state.percent)% remaining",
                    trailingText: nil
                ))
            }
        }
        power.start()

        bluetooth.onConnect = { [weak self] name in
            guard let self, self.settings.connectivityEnabled else { return }
            self.model.show(TransientNotification(
                systemImage: "headphones",
                tint: .green, title: name, subtitle: "Connected", trailingText: nil
            ))
        }
        bluetooth.onDisconnect = { [weak self] name in
            guard let self, self.settings.connectivityEnabled else { return }
            self.model.show(TransientNotification(
                systemImage: "headphones",
                tint: .secondary, title: name, subtitle: "Disconnected", trailingText: nil
            ))
        }
        bluetooth.start()

        focus.onChange = { [weak self] mode in
            guard let self, self.settings.focusEnabled, let mode else { return }
            self.model.show(TransientNotification(
                systemImage: "moon.fill",
                tint: .indigo, title: mode, subtitle: "Focus On", trailingText: nil
            ))
        }
        focus.start()
    }
}
