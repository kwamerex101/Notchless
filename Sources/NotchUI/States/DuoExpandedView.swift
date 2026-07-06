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

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            playerColumn
            Divider().overlay(Color.white.opacity(0.12))
            eventsColumn
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var playerColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: info?.title ?? "Not Playing",
                                font: .system(size: 13, weight: .semibold))
                        .frame(width: 150, height: 16)
                    Text(info?.artist ?? "—").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            HStack(spacing: 22) {
                button("backward.fill", 13) { onCommand(.previous) }
                button((info?.isPlaying ?? false) ? "pause.fill" : "play.fill", 15) { onCommand(.playPause) }
                button("forward.fill", 13) { onCommand(.next) }
            }
        }
        .frame(width: 210, alignment: .leading)
    }

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snap.weekdayCaps).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(nsColor: .systemPink))
                Spacer()
                Text(snap.dayNumber).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if snap.events.isEmpty {
                Text("No events today").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(snap.events.prefix(3)) { ev in
                    HStack(spacing: 6) {
                        Circle().fill(ev.color).frame(width: 6, height: 6)
                        Text(ev.title).font(.system(size: 11)).foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artwork: some View {
        Group {
            if let art = info?.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12))
                    .overlay(Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func button(_ name: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
        }.buttonStyle(.plain)
    }
}
