import Foundation

/// A countdown timer shown in the notch.
struct NotchTimerInfo: Equatable {
    var total: Int        // seconds
    var remaining: Int    // seconds
    var isRunning: Bool

    var isActive: Bool { total > 0 }
    var isFinished: Bool { total > 0 && remaining == 0 }

    var progress: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }

    var label: String {
        let h = remaining / 3600, m = (remaining % 3600) / 60, s = remaining % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
