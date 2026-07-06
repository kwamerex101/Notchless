import SwiftUI

/// A snapshot of the Mac's power source.
struct BatteryInfo: Equatable {
    var level: Int            // 0…100
    var isCharging: Bool
    var isPluggedIn: Bool     // on AC power
    var isCharged: Bool       // fully charged
    var timeRemaining: Int?   // minutes on battery (nil while estimating)
    var timeToFull: Int?      // minutes to full while charging

    var systemImage: String {
        if isCharged && isPluggedIn { return "battery.100.bolt" }
        if isCharging { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Tint for the compact glyph: green charging, red low, else white.
    var tint: Color {
        if isCharging || isPluggedIn { return .green }
        if level <= 20 { return .red }
        return .white
    }

    /// A short human status line for the expanded hub.
    var statusText: String {
        if isCharged && isPluggedIn { return "Fully charged" }
        if isCharging {
            if let toFull = timeToFull { return "\(formatted(toFull)) until full" }
            return "Charging"
        }
        if isPluggedIn { return "Plugged in" }
        if let remaining = timeRemaining { return "\(formatted(remaining)) remaining" }
        return "On battery"
    }

    private func formatted(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
}
