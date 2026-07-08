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
        case .playing, .duo, .none, .auto:
            artwork
        case .calendar:
            Text(calendar?.dayNumber ?? "")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        case .dictation:
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.14)))
        case .battery:
            Image(systemName: battery?.systemImage ?? "battery.100")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(battery?.tint ?? .white)
        case .stats:
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .claudeUsage:
            if SettingsStore.shared.claudeCompactStyle == .pie {
                MiniPie(slices: (claudeStats?.slices ?? []).map { (Double($0.value), $0.color) })
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle((timer?.isFinished ?? false) ? .orange : .white)
        case .clipboard:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .todos:
            Button {
                if let id = todos.next?.id { withAnimation(NotchMotion.micro) { todos.complete(id) } }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(NotchButtonStyle())
            .accessibilityLabel("Complete task")
        case .privacy:
            HStack(spacing: 4) {
                if privacy?.cameraActive ?? false { PulsingDot(color: .green) }
                if privacy?.micActive ?? false { PulsingDot(color: .orange) }
            }
        case .goals:
            GoalCompactView().leading
        case .meeting:
            if meetingPhase == .recording {
                PulsingDot(color: .red)
            } else {
                Image(systemName: "record.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .playing, .duo, .none, .auto:
            VisualizerBars(isPlaying: nowPlaying?.isPlaying ?? false,
                           color: glow ?? .white, height: 15, spectrum: audio.musicSpectrum)
                .frame(width: 38)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemPink))
        case .dictation:
            // A calm, muted idle waveform — springs to life (red) when recording.
            VisualizerBars(isPlaying: false, color: .white.opacity(0.55), height: 12)
                .frame(width: 20)
        case .battery:
            if SettingsStore.shared.batteryShowPercentage {
                Text("\(battery?.level ?? 0)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: battery?.level)
            }
        case .stats:
            Text("\(Int((stats?.cpu ?? 0) * 100))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: stats?.cpu)
        case .claudeUsage:
            Text(claudeCompactTrailing)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: claudeCompactTrailing)
        case .timer:
            Text(timer?.label ?? "0:00")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: timer?.label)
        case .clipboard:
            ClipboardBadge()
        case .todos:
            // Tight wing beside the notch — show a monogram (initials) instead of
            // a title that would just truncate to nothing legible.
            Text(todos.next?.initials ?? "✓")
                .font(.system(size: 13, weight: .bold).monospaced())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 60, alignment: .trailing)
        case .privacy:
            HStack(spacing: 6) {
                if privacy?.cameraActive ?? false {
                    Image(systemName: "camera.fill").foregroundStyle(.green)
                }
                if privacy?.micActive ?? false {
                    Image(systemName: "mic.fill").foregroundStyle(.orange)
                }
            }
            .font(.system(size: 13, weight: .semibold))
        case .goals:
            GoalCompactView().trailing
        case .meeting:
            switch meetingPhase {
            case .transcribing, .summarizing:
                ProgressView().controlSize(.small).tint(.white)
            case .some(.ready):
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    .font(.system(size: 13, weight: .semibold))
            case .some(.failed):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .font(.system(size: 13, weight: .semibold))
            default:
                EmptyView()
            }
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
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)))
            }
        }
        .matchedArtwork(artworkNamespace)
    }
}
