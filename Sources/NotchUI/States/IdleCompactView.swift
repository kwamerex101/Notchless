import SwiftUI

/// Compact idle content that lives in the notch band: album-art sliver on the
/// left edge, animated visualizer on the right (see PLAN.md §1.1).
struct IdleCompactView: View {
    let activity: NotchActivity
    let nowPlaying: NowPlayingInfo?
    let calendar: CalendarSnapshot?
    var battery: BatteryInfo? = nil
    var stats: SystemStats? = nil
    @ObservedObject var audio: AudioLevelsModel
    var timer: NotchTimerInfo? = nil
    var privacy: PrivacyStatus? = nil
    var claudeStats: ClaudeUsageStats? = nil
    var meetingPhase: MeetingPhase? = nil
    var meetingElapsed: TimeInterval? = nil
    var glow: Color? = nil
    /// All concurrently-live activities (for the pager dots) and the order used.
    var liveActivities: [NotchActivity] = []
    let metrics: NotchMetrics
    /// Shared namespace so the artwork sliver morphs into the expanded tile.
    var artworkNamespace: Namespace.ID? = nil
    @ObservedObject private var todos = TodoStore.shared

    /// Horizontal inset for edge content. The bottom corner curve reaches
    /// `topRadius + bottomRadius` (≈ 8 + 11 = 19pt) inward at its widest, so the
    /// inset must exceed that or the artwork's bottom corner gets clipped by the
    /// rounding (reads as "overflowing" the edge). 21 gives a small margin.
    private let edgeInset: CGFloat = 28

    private var claudeCompactTrailing: String {
        switch SettingsStore.shared.claudeCompactStyle {
        case .todayCost: return ClaudeUsageStats.moneyCompact(claudeStats?.todayCost ?? 0)
        default: return ClaudeUsageStats.format(claudeStats?.total ?? 0)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, edgeInset)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .playing, .none, .auto:
            artwork
        case .duo:
            // Spec §3 "Idle · Duo": art chip on the left, day number on the
            // right — not the Now Playing sliver's art + visualiser.
            artwork
        case .calendar:
            Text(calendar?.dayNumber ?? "")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NotchTheme.textPrimary)
        case .dictation:
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(NotchTheme.chip))
        case .battery:
            Image(systemName: battery?.systemImage ?? "battery.100")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(battery?.tint ?? NotchTheme.textPrimary)
        case .stats:
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
        case .claudeUsage:
            if SettingsStore.shared.claudeCompactStyle == .pie {
                MiniPie(slices: (claudeStats?.slices ?? []).map { (Double($0.value), $0.color) })
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
            }
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle((timer?.isFinished ?? false) ? NotchTheme.warning : NotchTheme.textPrimary)
        case .clipboard:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
        case .todos:
            // Completed tally — green, mirrors the active count on the right.
            // Hidden until the first completion so a bare "0" never shows.
            // Spec §3 "Idle · Todos": a check glyph beside the count, not a
            // filled number badge.
            if todos.completedCount > 0 {
                todoTally(system: "checkmark", count: todos.completedCount, color: NotchTheme.positive)
                    .accessibilityLabel("\(todos.completedCount) completed")
            }
        case .privacy:
            HStack(spacing: 4) {
                if privacy?.cameraActive ?? false { PulsingDot(color: NotchTheme.positive) }
                if privacy?.micActive ?? false { PulsingDot(color: NotchTheme.warning) }
            }
        case .goals:
            GoalCompactView().leading
        case .meeting:
            if meetingPhase == .recording {
                PulsingDot(color: NotchTheme.recording)
            } else {
                Image(systemName: "record.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .playing, .none, .auto:
            VisualizerBars(isPlaying: nowPlaying?.isPlaying ?? false,
                           color: glow ?? NotchTheme.textPrimary, height: 15, spectrum: audio.musicSpectrum)
                .frame(width: 38)
        case .duo:
            // Spec §3 "Idle · Duo": current day-of-month, 13 bold, primary —
            // same calendar source `.calendar` reads `dayNumber` from.
            Text(calendar?.dayNumber ?? "")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchTheme.textPrimary)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.85))
        case .dictation:
            // A calm, muted idle waveform — springs to life when recording.
            // Spec §3 "Idle · Dictation" wants a specific 4/7/10/6/4 zigzag,
            // not `VisualizerBars`' generic centre-weighted resting shape
            // (which reads as five near-identical dots at this height), so
            // it's drawn directly rather than through the shared component.
            DictationIdleBars()
                .frame(width: 20)
        case .battery:
            if SettingsStore.shared.batteryShowPercentage {
                Text("\(battery?.level ?? 0)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.default, value: battery?.level)
            }
        case .stats:
            Text("\(Int((stats?.cpu ?? 0) * 100))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: stats?.cpu)
        case .claudeUsage:
            Text(claudeCompactTrailing)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: claudeCompactTrailing)
        case .timer:
            Text(timer?.label ?? "0:00")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: timer?.label)
        case .clipboard:
            ClipboardBadge()
        case .todos:
            // Active tally — mirrors the green completed count on the left.
            // Spec §3 "Idle · Todos": an open-circle glyph beside the count.
            todoTally(system: "circle", count: todos.openCount, color: NotchTheme.textPrimary)
                .accessibilityLabel("\(todos.openCount) active")
        case .privacy:
            HStack(spacing: 6) {
                if privacy?.cameraActive ?? false {
                    Image(systemName: "camera.fill").foregroundStyle(NotchTheme.positive)
                }
                if privacy?.micActive ?? false {
                    Image(systemName: "mic.fill").foregroundStyle(NotchTheme.warning)
                }
            }
            .font(.system(size: 13, weight: .semibold))
        case .goals:
            GoalCompactView().trailing
        case .meeting:
            switch meetingPhase {
            case .recording:
                // Spec §3 "Idle · Meeting recording": elapsed `12:04`, 13
                // semibold, bright secondary.
                Text(Self.meetingElapsedLabel(meetingElapsed ?? 0))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textBrightSecondary)
            case .transcribing, .summarizing:
                ProgressView().controlSize(.small).tint(NotchTheme.textPrimary)
            case .some(.ready):
                Image(systemName: "checkmark.circle").foregroundStyle(NotchTheme.positive)
                    .font(.system(size: 13, weight: .semibold))
            case .some(.failed):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(NotchTheme.warning)
                    .font(.system(size: 13, weight: .semibold))
            default:
                EmptyView()
            }
        }
    }

    /// `m:ss` (or `h:mm:ss` past an hour) — mirrors `MeetingExpandedView`'s
    /// `timeString`, which is private to that file.
    private static func meetingElapsedLabel(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// A glyph beside its count — the task tally wings, spec §3 "Idle · Todos":
    /// "green check + count" / "open circle + count", not a filled badge.
    private func todoTally(system: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.default, value: count)
        }
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let art = nowPlaying?.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NotchTheme.artworkPlaceholder)
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(NotchTheme.textPrimary.opacity(0.7)))
            }
        }
        .matchedArtwork(artworkNamespace)
    }
}

/// The static waveform for Idle · Dictation. Spec §3: five 3pt-wide bars at
/// heights 4/7/10/6/4, radius 1.5, opacity 0.55 — a fixed zigzag, not an
/// animated or centre-weighted shape.
private struct DictationIdleBars: View {
    private let heights: [CGFloat] = [4, 7, 10, 6, 4]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(NotchTheme.textPrimary.opacity(0.55))
                    .frame(width: 3, height: heights[i])
            }
        }
    }
}
