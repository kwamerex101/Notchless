import SwiftUI

/// The expanded Claude usage panel: the current 5-hour session and weekly spend
/// with reset timers, recent daily spend, and the token-split legend.
struct ClaudeStatsExpandedView: View {
    let stats: ClaudeUsageStats?
    let metrics: NotchMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Claude usage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(ClaudeUsageStats.format(stats?.total ?? 0)) tokens")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            windowRow(title: "Session", cost: stats?.sessionCost ?? 0,
                      reset: stats?.sessionResetIn, tint: .blue)
            windowRow(title: "This week", cost: stats?.weekCost ?? 0, reset: nil, tint: .purple)

            Divider().overlay(Color.white.opacity(0.08))

            spendRow("Today", stats?.todayCost ?? 0)
            spendRow("Yesterday", stats?.yesterdayCost ?? 0)
            spendRow("Last 30 days", stats?.last30Cost ?? 0)

            HStack(spacing: 12) {
                ForEach(stats?.slices ?? [], id: \.label) { slice in
                    HStack(spacing: 4) {
                        Circle().fill(slice.color).frame(width: 6, height: 6)
                        Text(ClaudeUsageStats.format(slice.value))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                Text("est.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.top, 1)
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A window (session/week) with a small usage bar + reset countdown.
    private func windowRow(title: String, cost: Double, reset: TimeInterval?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                Spacer()
                if let reset {
                    Text("Resets in \(ClaudeUsageStats.countdown(reset))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Text(ClaudeUsageStats.money(cost))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 74, alignment: .trailing)
            }
        }
    }

    private func spendRow(_ title: String, _ cost: Double) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text("\(ClaudeUsageStats.money(cost)) est.")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
