import SwiftUI

/// Duo panel: compact now-playing on the left, date + event list on the right
/// (see PLAN.md §1.1, frames f_077).
struct DuoExpandedView: View {
    let info: NowPlayingInfo?
    let snapshot: CalendarSnapshot?
    let metrics: NotchMetrics
    var onCommand: (MediaCommand) -> Void = { _ in }

    private var snap: CalendarSnapshot {
        snapshot ?? CalendarSnapshot(date: Date(), events: [])
    }

    private static let timeRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            playerColumn
            Rectangle().fill(NotchTheme.divider).frame(width: 1).frame(maxHeight: .infinity)
            eventsColumn
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var playerColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: info?.title ?? "Not Playing",
                                font: .system(size: 13, weight: .semibold),
                                color: NotchTheme.textPrimary)
                        .frame(width: 150, height: 16)
                    Text(info?.artist ?? "—").font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textSecondary).lineLimit(1)
                }
            }
            HStack(spacing: 20) {
                button("backward.fill", 12) { onCommand(.previous) }
                playPauseButton
                button("forward.fill", 12) { onCommand(.next) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snap.weekdayCaps + " " + snap.dayNumber)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(NotchTheme.textSecondary)
            if snap.events.isEmpty {
                Text("No events today").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
            } else if let first = snap.events.first {
                Text(first.title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                // No location field on `NotchEvent` — the mock's "· Zoom" suffix
                // has no data source, so this shows the time range only.
                Text(Self.timeRangeFormatter.string(from: first.start) + " – "
                     + Self.timeRangeFormatter.string(from: first.end))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary).lineLimit(1)
            }
        }
        .frame(width: 190, alignment: .leading)
    }

    private var artwork: some View {
        Group {
            if let art = info?.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(NotchTheme.artworkPlaceholder)
                    .overlay(Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(NotchTheme.textSecondary))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var playPauseButton: some View {
        Button { onCommand(.playPause) } label: {
            Image(systemName: (info?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NotchTheme.chip))
        }.buttonStyle(.plain)
    }

    private func button(_ name: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.85))
        }.buttonStyle(.plain)
    }
}
