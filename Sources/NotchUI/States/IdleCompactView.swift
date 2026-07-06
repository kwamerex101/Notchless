import SwiftUI

/// Compact idle content that lives in the notch band: album-art sliver on the
/// left edge, animated visualizer on the right (see PLAN.md §1.1).
struct IdleCompactView: View {
    let activity: NotchActivity
    let nowPlaying: NowPlayingInfo?
    let calendar: CalendarSnapshot?
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
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .playing, .duo, .none, .auto:
            VisualizerBars(isPlaying: nowPlaying?.isPlaying ?? false, height: 12)
                .frame(width: 20)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemPink))
        case .dictation:
            // A calm, muted idle waveform — springs to life (red) when recording.
            VisualizerBars(isPlaying: false, color: .white.opacity(0.55), height: 12)
                .frame(width: 20)
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
