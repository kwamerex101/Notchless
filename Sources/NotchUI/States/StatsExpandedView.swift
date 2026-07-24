import SwiftUI

/// The expanded system-stats panel: CPU, memory, and network at a glance.
struct StatsExpandedView: View {
    let stats: SystemStats?
    let metrics: NotchMetrics

    private var settings: SettingsStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.statsShowCPU {
                row(label: "CPU", fraction: stats?.cpu ?? 0,
                    value: "\(Int((stats?.cpu ?? 0) * 100))%")
            }
            if settings.statsShowMemory {
                row(label: "Memory", fraction: stats?.memoryFraction ?? 0,
                    value: SystemStats.formatBytes(stats?.memoryUsed ?? 0))
            }
            if settings.statsShowNetwork {
                network
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 19)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(label: String, fraction: Double, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchTheme.track)
                    Capsule().fill(NotchTheme.fill)
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                        .animation(NotchMotion.fill, value: fraction)
                }
            }
            .frame(height: 5)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var network: some View {
        HStack(spacing: 10) {
            Text("Network")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 56, alignment: .leading)
            Spacer()
            Text("↓ \(SystemStats.formatRate(stats?.networkDown ?? 0))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.textBrightSecondary)
            Text("↑ \(SystemStats.formatRate(stats?.networkUp ?? 0))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.textBrightSecondary)
        }
    }
}
