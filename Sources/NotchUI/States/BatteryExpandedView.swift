import SwiftUI

/// The expanded battery hub: a large charge ring, status line, and time detail.
struct BatteryExpandedView: View {
    let battery: BatteryInfo?
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                Text(titleLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
                Text("\(battery?.level ?? 0)%")
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textPrimary)
                Text(battery?.statusText ?? "No battery")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var level: Double { Double(battery?.level ?? 0) / 100 }

    /// "Battery" alone, or "Battery · Charging" while on AC.
    private var titleLine: String {
        (battery?.isCharging ?? false) ? "Battery · Charging" : "Battery"
    }

    /// Colour only where it means something: the ring stays `positive` while
    /// charging or at a healthy level, and turns `recording` (red) once the
    /// charge drops to or below the user's low-battery threshold.
    private var ringColor: Color {
        let isLow = !(battery?.isCharging ?? false) && (battery?.level ?? 100) <= SettingsStore.shared.batteryLowThreshold
        return isLow ? NotchTheme.recording : NotchTheme.positive
    }

    private var ring: some View {
        Circle()
            .stroke(NotchTheme.ringTrack, lineWidth: 7)
            .overlay(
                Circle()
                    .trim(from: 0, to: level)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(NotchMotion.fill, value: level)
            )
            .frame(width: 64, height: 64)
    }
}
