import SwiftUI

/// The 4-bar audio visualizer shown beside now-playing content. Decorative:
/// bars breathe on a timer when playing, rest flat when paused (Alcove's bars
/// are not a real spectrum — see PLAN.md §1.4).
struct VisualizerBars: View {
    var isPlaying: Bool
    var color: Color = .white
    var barCount: Int = 4
    var height: CGFloat = 14
    /// When non-empty, real live audio-band levels (low→high) drive the bars;
    /// otherwise they fall back to a decorative breathing animation.
    var spectrum: [CGFloat] = []

    @State private var phase: [CGFloat]

    init(isPlaying: Bool, color: Color = .white, barCount: Int = 4, height: CGFloat = 14, spectrum: [CGFloat] = []) {
        self.isPlaying = isPlaying
        self.color = color
        self.barCount = barCount
        self.height = height
        self.spectrum = spectrum
        _phase = State(initialValue: (0..<barCount).map { _ in CGFloat.random(in: 0.3...1) })
    }

    private let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    private var useSpectrum: Bool { isPlaying && !spectrum.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: max(2, height * level(i)))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: spectrum)
        .animation(.easeInOut(duration: 0.16), value: phase)
        .onReceive(timer) { _ in
            guard isPlaying, !useSpectrum else { return }
            phase = phase.map { _ in CGFloat.random(in: 0.25...1) }
        }
    }

    private func level(_ i: Int) -> CGFloat {
        if useSpectrum {
            return spectrum[min(i, spectrum.count - 1)]
        }
        return isPlaying ? phase[i] : 0.2
    }
}
