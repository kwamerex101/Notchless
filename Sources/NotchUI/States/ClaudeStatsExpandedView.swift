import SwiftUI

/// The expanded Claude usage panel. Which sections show — session, weekly,
/// daily spend, chart, token legend — is driven by the Claude Usage settings.
struct ClaudeStatsExpandedView: View {
    let stats: ClaudeUsageStats?
    let metrics: NotchMetrics

    private var settings: SettingsStore { .shared }

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

            if settings.claudeShowChart {
                MiniLineChart(values: chartValues, color: settings.claudeChartCost ? .orange : .green)
                    .frame(height: 42)
            }

            if settings.claudeShowSession {
                windowRow(title: "Session", cost: stats?.sessionCost ?? 0, reset: stats?.sessionResetIn)
            }
            if settings.claudeShowWeek {
                windowRow(title: "This week", cost: stats?.weekCost ?? 0, reset: nil)
            }

            if settings.claudeShowSpend {
                Divider().overlay(Color.white.opacity(0.08))
                spendRow("Today", stats?.todayCost ?? 0)
                spendRow("Yesterday", stats?.yesterdayCost ?? 0)
                spendRow("Last 30 days", stats?.last30Cost ?? 0)
            }

            if settings.claudeShowLegend {
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
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The daily series sliced to the user's window, as tokens or cost.
    private var chartValues: [Double] {
        let days = min(settings.claudeChartDays, stats?.daily.count ?? 0)
        let series = Array((stats?.daily ?? []).suffix(days))
        return series.map { settings.claudeChartCost ? $0.cost : Double($0.tokens) }
    }

    private func windowRow(title: String, cost: Double, reset: TimeInterval?) -> some View {
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
