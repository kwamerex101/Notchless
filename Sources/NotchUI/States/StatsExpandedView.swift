import SwiftUI

/// The expanded system-stats panel: CPU, memory, and network at a glance.
struct StatsExpandedView: View {
    let stats: SystemStats?
    let metrics: NotchMetrics

    private var settings: SettingsStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.statsShowCPU {
                row(icon: "cpu", label: "CPU", fraction: stats?.cpu ?? 0,
                    value: "\(Int((stats?.cpu ?? 0) * 100))%", tint: .green)
            }
            if settings.statsShowMemory {
                row(icon: "memorychip", label: "Memory", fraction: stats?.memoryFraction ?? 0,
                    value: SystemStats.formatBytes(stats?.memoryUsed ?? 0), tint: .blue)
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

    private func row(icon: String, label: String, fraction: Double, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                        .animation(NotchMotion.fill, value: fraction)
                }
            }
            .frame(height: 6)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 62, alignment: .trailing)
        }
    }

    private var network: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 20)
            Text("Network")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 62, alignment: .leading)
            Spacer()
            Label(SystemStats.formatRate(stats?.networkDown ?? 0), systemImage: "arrow.down")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
            Label(SystemStats.formatRate(stats?.networkUp ?? 0), systemImage: "arrow.up")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
