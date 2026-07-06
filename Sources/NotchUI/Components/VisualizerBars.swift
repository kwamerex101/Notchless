import SwiftUI

/// A compact audio visualizer shown beside now-playing content. Mirrors
/// symmetrically from the centre bar; when a live `spectrum` is present it
/// tracks real audio, otherwise it breathes on a timer while playing and rests
/// low when paused.
struct VisualizerBars: View {
    var isPlaying: Bool
    var color: Color = .white
    var barCount: Int = 5
    var height: CGFloat = 14
    /// When non-empty, real live audio-band levels (low→high) drive the bars.
    var spectrum: [CGFloat] = []

    @State private var phase: [CGFloat]

    init(isPlaying: Bool, color: Color = .white, barCount: Int = 5, height: CGFloat = 14, spectrum: [CGFloat] = []) {
        self.isPlaying = isPlaying
        self.color = color
        self.barCount = barCount
        self.height = height
        self.spectrum = spectrum
        _phase = State(initialValue: Self.freshPhase(barCount))
    }

    private let timer = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    private var useSpectrum: Bool { isPlaying && !spectrum.isEmpty }
    private var center: Int { (barCount - 1) / 2 }

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(isPlaying ? 1 : 0.55))
                    .frame(width: 3.5, height: max(3, height * level(i)))
                    .shadow(color: color.opacity(isPlaying ? 0.6 : 0), radius: 3)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.16, dampingFraction: 0.6), value: spectrum)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: phase)
        .onReceive(timer) { _ in
            guard isPlaying, !useSpectrum else { return }
            phase = Self.freshPhase(barCount)
        }
    }

    /// Height fraction for a bar, mirrored around the centre so the shape reads
    /// as a symmetric equalizer.
    private func level(_ i: Int) -> CGFloat {
        let distance = abs(i - center)
        if useSpectrum {
            // Bolder swing: amplify the band level and clamp.
            return max(0.16, min(1, spectrum[min(distance, spectrum.count - 1)] * 1.35))
        }
        if isPlaying {
            // Taller toward the centre for a lively equalizer shape.
            let falloff = 1 - CGFloat(distance) / CGFloat(center + 1) * 0.4
            return phase[i] * falloff
        }
        // Resting: a gentle centre-weighted line, not flat dots.
        return 0.18 + (1 - CGFloat(distance) / CGFloat(center + 1)) * 0.12
    }

    private static func freshPhase(_ count: Int) -> [CGFloat] {
        (0..<count).map { _ in CGFloat.random(in: 0.3...1) }
    }
}
