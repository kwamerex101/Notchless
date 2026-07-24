import SwiftUI

/// The full player panel: artwork + scrolling title/artist + visualizer, a
/// draggable scrubber, and the transport row (see PLAN.md §1.1).
struct NowPlayingExpandedView: View {
    let info: NowPlayingInfo?
    @ObservedObject var audio: AudioLevelsModel
    let metrics: NotchMetrics
    var glow: Color? = nil
    var onCommand: (MediaCommand) -> Void = { _ in }
    var onActivateSource: () -> Void = {}
    var artworkNamespace: Namespace.ID? = nil

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var scrubHovering = false
    @State private var showingOutputPicker = false

    var body: some View {
        VStack(spacing: 10) {
            header
            scrubber
            transport
        }
        .padding(.top, metrics.notchHeight + 6)
        .padding(.horizontal, 19)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Album-art glow is painted at the panel level (NotchRootView) so it sits
        // behind the tab strip too and both share one background.
    }

    private var header: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info?.title ?? "Not Playing",
                            font: .system(size: 14, weight: .semibold),
                            color: NotchTheme.textPrimary)
                    .frame(height: 18)
                Text(info?.artist ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            // Monochrome white — the album-art glow no longer tints content (flat-dark spec §1).
            VisualizerBars(isPlaying: info?.isPlaying ?? false, color: .white,
                           barCount: 5, height: 18, spectrum: audio.musicSpectrum)
                .frame(width: 44)
        }
    }

    private var artwork: some View {
        Group {
            if let art = info?.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(NotchTheme.artworkPlaceholder)
                    .overlay(Image(systemName: "music.note").foregroundStyle(NotchTheme.textSecondary))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .matchedArtwork(artworkNamespace)
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
        // Drive the position from a local 2 Hz clock while playing, so the
        // fill and time labels advance smoothly without the model republishing.
        Group {
            if info?.isPlaying == true {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in scrubberRow(now: ctx.date) }
            } else {
                scrubberRow(now: Date())
            }
        }
    }

    private func scrubberRow(now: Date) -> some View {
        let progress = scrubbing ? scrubValue : (info?.progress(at: now) ?? 0)
        let trackHeight: CGFloat = (scrubHovering || scrubbing) ? 9 : 6
        return HStack(spacing: 8) {
            Text(info?.elapsedText(at: now) ?? "0:00")
                .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 34, alignment: .leading)
                .contentTransition(.numericText())
            GeometryReader { geo in
                let fillWidth = geo.size.width * CGFloat(progress)
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchTheme.track)
                    Capsule().fill(NotchTheme.fill).frame(width: fillWidth)
                        // Non-scrubbing progress glides between the 2 Hz updates.
                        .animation(scrubbing ? nil : .linear(duration: 0.5), value: fillWidth)
                    // A grab knob at the fill edge while hovering/scrubbing.
                    if scrubHovering || scrubbing {
                        Circle().fill(NotchTheme.fill).frame(width: 11, height: 11)
                            .offset(x: min(max(fillWidth - 5.5, 0), geo.size.width - 11))
                    }
                }
                // Tall invisible hit area centred on the thin track.
                .frame(height: geo.size.height, alignment: .center)
                .contentShape(Rectangle().inset(by: -8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            scrubbing = true
                            scrubValue = min(1, max(0, v.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            if let d = info?.duration, d > 0 { onCommand(.seek(scrubValue * d)) }
                            scrubbing = false
                            if SettingsStore.shared.hapticFeedback { HapticService.tap() }
                        }
                )
            }
            .frame(height: trackHeight)
            .animation(NotchMotion.micro, value: trackHeight)
            .onHover { scrubHovering = $0 }
            Text(info?.remainingText(at: now) ?? "-0:00")
                .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private var transport: some View {
        let settings = SettingsStore.shared
        let order = NowPlayingTransport.ordered(showShuffle: settings.npShowShuffle,
                                                 showSkip15: settings.npShowSkip15)
        return HStack(spacing: 26) {
            ForEach(order, id: \.self) { kind in
                transportButtonView(for: kind)
            }
            outputPicker
        }
    }

    @ViewBuilder
    private func transportButtonView(for kind: TransportButtonKind) -> some View {
        switch kind {
        case .shuffle:
            transportButton("shuffle", size: 13, label: "Shuffle") { onCommand(.toggleShuffle) }
        case .rewind15:
            transportButton("gobackward.15", size: 15, label: "Back 15s") {
                let e = info?.elapsed(at: Date()) ?? 0
                onCommand(.seek(max(0, e - 15)))
            }
        case .previous:
            transportButton("backward.fill", size: 15, label: "Previous") { onCommand(.previous) }
        case .playPause:
            Button { onCommand(.playPause) } label: {
                Image(systemName: (info?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(NotchTheme.chip))
            }
            .buttonStyle(NotchButtonStyle())
            .accessibilityLabel((info?.isPlaying ?? false) ? "Pause" : "Play")
        case .next:
            transportButton("forward.fill", size: 15, label: "Next") { onCommand(.next) }
        case .forward15:
            transportButton("goforward.15", size: 15, label: "Forward 15s") {
                let e = info?.elapsed(at: Date()) ?? 0
                let d = info?.duration ?? 0
                onCommand(.seek(d > 0 ? min(d, e + 15) : e + 15))
            }
        }
    }

    // A plain `Button` + `.popover`, not `Menu` — `Menu`'s label is NSMenu-backed
    // and `ImageRenderer`'s single synchronous offscreen pass can't draw it,
    // painting a broken-image glyph instead (independent of the symbol name;
    // confirmed by swapping in a bare `Image`, which renders correctly). This
    // keeps the same "reach the output device from the transport row"
    // capability without a control offscreen rendering can't paint.
    private var outputPicker: some View {
        Button {
            showingOutputPicker = true
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio output")
        .popover(isPresented: $showingOutputPicker, arrowEdge: .bottom) {
            outputDeviceList
        }
    }

    private var outputDeviceList: some View {
        let service = AudioOutputService.shared
        let current = service.currentDefault()
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(service.devices()) { device in
                Button {
                    service.setDefault(device.id)
                    showingOutputPicker = false
                } label: {
                    if device.id == current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private func transportButton(_ name: String, size: CGFloat, label: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.85))
        }
        .buttonStyle(NotchButtonStyle())
        .accessibilityLabel(label)
    }
}
