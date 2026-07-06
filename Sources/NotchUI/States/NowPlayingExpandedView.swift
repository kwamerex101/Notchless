import SwiftUI

/// The full player panel: artwork + scrolling title/artist + visualizer, a
/// draggable scrubber, and the transport row (see PLAN.md §1.1).
struct NowPlayingExpandedView: View {
    let info: NowPlayingInfo?
    var musicSpectrum: [CGFloat] = []
    let metrics: NotchMetrics
    var glow: Color? = nil
    var onCommand: (MediaCommand) -> Void = { _ in }
    var onActivateSource: () -> Void = {}

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            header
            scrubber
            transport
        }
        .padding(.top, metrics.notchHeight + 6)
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .topLeading) {
            if let glow {
                RadialGradient(colors: [glow.opacity(0.38), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 320)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info?.title ?? "Not Playing",
                            font: .system(size: 14, weight: .semibold))
                    .frame(height: 18)
                Text(info?.artist ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VisualizerBars(isPlaying: info?.isPlaying ?? false, height: 16, spectrum: musicSpectrum)
                .frame(width: 22)
        }
    }

    private var artwork: some View {
        Group {
            if let art = info?.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6)))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if info?.bundleIdentifier != nil {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .offset(x: 3, y: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivateSource() }
        .help("Open in the app that's playing")
    }

    private var scrubber: some View {
        let progress = scrubbing ? scrubValue : (info?.progress ?? 0)
        return HStack(spacing: 8) {
            Text(info?.elapsedText ?? "0:00")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white).frame(width: geo.size.width * CGFloat(progress))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            scrubbing = true
                            scrubValue = min(1, max(0, v.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            if let d = info?.duration, d > 0 { onCommand(.seek(scrubValue * d)) }
                            scrubbing = false
                        }
                )
            }
            .frame(height: 6)
            Text(info?.remainingText ?? "-0:00")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var transport: some View {
        HStack(spacing: 26) {
            transportButton("shuffle", size: 13) { onCommand(.toggleShuffle) }
            transportButton("backward.fill", size: 15) { onCommand(.previous) }
            Button { onCommand(.playPause) } label: {
                Image(systemName: (info?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }.buttonStyle(.plain)
            transportButton("forward.fill", size: 15) { onCommand(.next) }
            outputPicker
        }
    }

    private var outputPicker: some View {
        Menu {
            let service = AudioOutputService.shared
            let current = service.currentDefault()
            ForEach(service.devices()) { device in
                Button {
                    service.setDefault(device.id)
                } label: {
                    if device.id == current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func transportButton(_ name: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }.buttonStyle(.plain)
    }
}
