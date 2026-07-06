import SwiftUI

/// The expanded Claude usage panel: a daily-tokens line chart plus a legend of
/// the input / output / cache split and the total.
struct ClaudeStatsExpandedView: View {
    let stats: ClaudeUsageStats?
    let metrics: NotchMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude usage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(ClaudeUsageStats.format(stats?.total ?? 0)) tokens")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            MiniLineChart(values: (stats?.daily ?? []).map { Double($0.tokens) }, color: .green)
                .frame(height: 54)

            HStack(spacing: 14) {
                ForEach(stats?.slices ?? [], id: \.label) { slice in
                    HStack(spacing: 5) {
                        Circle().fill(slice.color).frame(width: 7, height: 7)
                        Text(slice.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        Text(ClaudeUsageStats.format(slice.value))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                Text("Last 14 days").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
