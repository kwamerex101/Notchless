import SwiftUI

/// Compact idle content that lives in the notch band: album-art sliver on the
/// left edge, animated visualizer on the right (see PLAN.md §1.1).
struct IdleCompactView: View {
    let activity: NotchActivity
    let nowPlaying: NowPlayingInfo?
    let calendar: CalendarSnapshot?
    var battery: BatteryInfo? = nil
    var stats: SystemStats? = nil
    var musicSpectrum: [CGFloat] = []
    var timer: NotchTimerInfo? = nil
    var privacy: PrivacyStatus? = nil
    let metrics: NotchMetrics

    /// Horizontal inset for edge content. The bottom corner curve reaches
    /// `topRadius + bottomRadius` (≈ 8 + 11 = 19pt) inward at its widest, so the
    /// inset must exceed that or the artwork's bottom corner gets clipped by the
    /// rounding (reads as "overflowing" the edge). 21 gives a small margin.
    private let edgeInset: CGFloat = 28

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
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle((timer?.isFinished ?? false) ? .orange : .white)
        case .clipboard:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .privacy:
            HStack(spacing: 4) {
                if privacy?.cameraActive ?? false {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                }
                if privacy?.micActive ?? false {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                }
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .playing, .duo, .none, .auto:
            VisualizerBars(isPlaying: nowPlaying?.isPlaying ?? false, height: 12, spectrum: musicSpectrum)
                .frame(width: 20)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemPink))
        case .dictation:
            // A calm, muted idle waveform — springs to life (red) when recording.
            VisualizerBars(isPlaying: false, color: .white.opacity(0.55), height: 12)
                .frame(width: 20)
        case .battery:
            Text("\(battery?.level ?? 0)%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .stats:
            Text("\(Int((stats?.cpu ?? 0) * 100))%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        case .timer:
            Text(timer?.label ?? "0:00")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        case .clipboard:
            ClipboardBadge()
        case .privacy:
            Text(privacy?.label ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var artwork: some View {
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
}
