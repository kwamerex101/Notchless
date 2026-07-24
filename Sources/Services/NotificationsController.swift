import SwiftUI

/// Turns system events (battery, Bluetooth, Focus) into transient notch
/// notifications, gated by the per-category settings toggles.
@MainActor
final class NotificationsController {
    private let model: NotchViewModel
    private let power = PowerService()
    private let bluetooth = BluetoothService()
    private let focus = FocusService()
    private let network = NetworkService()

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
                    tint: state.isCharging ? NotchTheme.positive : .white,
                    title: state.isCharging ? "Charging" : "On Battery",
                    subtitle: state.isCharging ? self.chargingSubtitle(state) : nil,
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
                tint: NotchTheme.link, title: name, subtitle: "Connected", trailingText: nil
            ))
        }
        bluetooth.onDisconnect = { [weak self] name in
            guard let self, self.settings.connectivityEnabled else { return }
            self.model.show(TransientNotification(
                systemImage: "headphones",
                tint: NotchTheme.link, title: name, subtitle: "Disconnected", trailingText: nil
            ))
        }
        bluetooth.start()

        focus.onChange = { [weak self] mode in
            guard let self, self.settings.focusEnabled else { return }
            self.model.show(TransientNotification(
                systemImage: mode == nil ? "moon.zzz" : "moon.fill",
                tint: mode == nil ? .secondary : NotchTheme.focus,
                title: mode ?? "Focus",
                // Design shows "Focus on until 6:00 PM", but FocusService only
                // reports the mode identifier — the DND assertions file it reads
                // (Sources/Services/FocusService.swift) has no schedule end time.
                subtitle: mode == nil ? "Focus Off" : "Focus On",
                trailingText: nil
            ))
        }
        focus.start()

        network.onChange = { [weak self] connectivity in
            guard let self, self.settings.connectivityEnabled else { return }
            switch connectivity {
            case .online:
                self.model.show(TransientNotification(
                    systemImage: "wifi", tint: NotchTheme.positive,
                    title: "Back online", subtitle: nil, trailingText: nil
                ))
            case .noInternet:
                // Link is up (Wi-Fi joined) but there's no route to the internet —
                // captive portal, router with no WAN, etc.
                self.model.show(TransientNotification(
                    systemImage: "wifi.exclamationmark", tint: NotchTheme.warning,
                    title: "No Internet", subtitle: "Wi-Fi is connected without internet",
                    trailingText: nil
                ))
            case .offline:
                self.model.show(TransientNotification(
                    systemImage: "wifi.slash", tint: NotchTheme.warning,
                    title: "No Internet", subtitle: "Check your connection", trailingText: nil
                ))
            }
        }
        network.start()
    }

    /// "MacBook Pro — 2:14 until full" while IOKit has an estimate, "— Fully
    /// charged" at 100%, or just the device name when the estimate is still
    /// calculating (kIOPSTimeToFullChargeKey == -1).
    private func chargingSubtitle(_ state: PowerState) -> String {
        let device = PowerService.deviceName
        if state.percent >= 100 {
            return "\(device) — Fully charged"
        }
        guard let minutes = state.timeToFullMinutes else { return device }
        return "\(device) — \(PowerService.formatTimeToFull(minutes)) until full"
    }
}
