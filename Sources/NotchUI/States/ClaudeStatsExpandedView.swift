import SwiftUI

/// The expanded Claude usage panel. Spec §3 "Expanded · Claude usage": donut,
/// legend, and a Today/Week footer only. The trend chart, session countdown,
/// and daily-spend breakdown that used to live here are settings-pane-only
/// now (see `claudeShowChart` / `claudeShowSession` / `claudeShowSpend`).
struct ClaudeStatsExpandedView: View {
    let stats: ClaudeUsageStats?
    let metrics: NotchMetrics
    /// Injected rather than read from `.shared` so the debug-dump harness's
    /// isolated settings drive these display toggles too (see
    /// `DebugStateDump.makeIsolatedSettings`).
    let settings: SettingsStore

    var body: some View {
        // Spec §3 "Expanded · Claude usage": donut + legend + Today/Week
        // footer only — the trend chart, session countdown, and
        // yesterday/last-30-days spend breakdown overflowed the 196pt panel
        // and were cut per the user's decision. Their settings toggles
        // (`claudeShowChart`, `claudeShowSession`, `claudeShowSpend`) still
        // exist and gate other surfaces; they're simply not read here.
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                donut
                if settings.claudeShowLegend {
                    legend
                }
            }

            footer
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Three-segment donut — input / output / cache — shaded on the white
    /// opacity ramp rather than distinct hues.
    private var donut: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 30
            let total = Double(stats?.total ?? 0)
            guard total > 0 else {
                var track = Path()
                track.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                context.stroke(track, with: .color(NotchTheme.ringTrack), style: StrokeStyle(lineWidth: 10))
                return
            }
            var start = Angle.degrees(-90)
            for segment in donutSegments where segment.value > 0 {
                let sweep = Angle.degrees(segment.value / total * 360)
                let end = start + sweep
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(path, with: .color(.white.opacity(segment.opacity)), style: StrokeStyle(lineWidth: 10))
                start = end
            }
        }
        .frame(width: 76, height: 76)
    }

    /// (token count, ramp opacity) for input / output / cache, in that order.
    private var donutSegments: [(value: Double, opacity: Double)] {
        [
            (Double(stats?.input ?? 0), 0.9),
            (Double(stats?.output ?? 0), 0.45),
            (Double(stats?.cache ?? 0), 0.2)
        ]
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(label: "Input", value: stats?.input ?? 0, opacity: 0.9)
            legendRow(label: "Output", value: stats?.output ?? 0, opacity: 0.45)
            legendRow(label: "Cache", value: stats?.cache ?? 0, opacity: 0.2)
        }
    }

    private func legendRow(label: String, value: Int, opacity: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(opacity))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textBrightSecondary)
            Spacer(minLength: 10)
            Text(ClaudeUsageStats.format(value))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
        }
    }

    /// `Today $x` · `Week $x` — Today always shows per spec; Week honours
    /// the "This week" settings toggle, same as it gated the row before.
    private var footer: some View {
        HStack(spacing: 12) {
            Text("Today \(ClaudeUsageStats.money(stats?.todayCost ?? 0))")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.textSecondary)
            if settings.claudeShowWeek {
                Text("Week \(ClaudeUsageStats.money(stats?.weekCost ?? 0))")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
        }
    }
}
