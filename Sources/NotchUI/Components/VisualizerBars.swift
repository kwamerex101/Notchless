import SwiftUI

/// A compact audio visualizer shown beside now-playing content. Mirrors
/// symmetrically from the centre bar; when a live `spectrum` is present it
/// tracks real audio, otherwise it breathes on a timer while playing and rests
/// low when paused.
///
/// The decorative timer lives in `DancingBars`, which only exists in the view
/// tree when actually dancing — paused and spectrum-driven bars register no
/// timer at all. Honors Reduce Motion by resting.
struct VisualizerBars: View {
    var isPlaying: Bool
    var color: Color = .white
    var barCount: Int = 5
    var height: CGFloat = 14
    /// When non-empty, real live audio-band levels (low→high) drive the bars.
    var spectrum: [CGFloat] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var center: Int { (barCount - 1) / 2 }
    private var useSpectrum: Bool { isPlaying && !spectrum.isEmpty }

    var body: some View {
        if isPlaying, spectrum.isEmpty, !reduceMotion {
            DancingBars(color: color, barCount: barCount, height: height)
        } else {
            BarStack(levels: staticLevels, color: color, isPlaying: isPlaying, height: height)
                .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.6), value: spectrum)
        }
    }

    /// Heights for the spectrum-driven or resting cases (no timer).
    private var staticLevels: [CGFloat] {
        (0..<barCount).map { i in
            let distance = abs(i - center)
            if useSpectrum {
                // Bolder swing: amplify the band level and clamp.
                return max(0.16, min(1, spectrum[min(distance, spectrum.count - 1)] * 1.35))
            }
            // Resting: a gentle centre-weighted line, not flat dots.
            return 0.18 + (1 - CGFloat(distance) / CGFloat(center + 1)) * 0.12
        }
    }
}

/// The bar row itself. One group-level glow instead of a shadow per capsule.
private struct BarStack: View {
    let levels: [CGFloat]
    let color: Color
    let isPlaying: Bool
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(isPlaying ? 1 : 0.55))
                    .frame(width: 3.5, height: max(3, height * levels[i]))
            }
        }
        .frame(height: height)
        .shadow(color: color.opacity(isPlaying ? 0.5 : 0), radius: 3)
    }
}

/// The decorative equalizer dance. Owns the only timer; instantiated solely
/// while playing without a live spectrum, so paused/spectrum bars cost nothing.
private struct DancingBars: View {
    let color: Color
    let barCount: Int
    let height: CGFloat

    @State private var phase: [CGFloat]
    private let timer = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    init(color: Color, barCount: Int, height: CGFloat) {
        self.color = color
        self.barCount = barCount
        self.height = height
        _phase = State(initialValue: Self.freshPhase(barCount))
    }

    private var center: Int { (barCount - 1) / 2 }

    var body: some View {
        BarStack(levels: danceLevels, color: color, isPlaying: true, height: height)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: phase)
            .onReceive(timer) { _ in phase = Self.freshPhase(barCount) }
    }

    /// Taller toward the centre for a lively equalizer shape.
    private var danceLevels: [CGFloat] {
        (0..<barCount).map { i in
            let distance = abs(i - center)
            let falloff = 1 - CGFloat(distance) / CGFloat(center + 1) * 0.4
            return phase[i] * falloff
        }
    }

    private static func freshPhase(_ count: Int) -> [CGFloat] {
        (0..<count).map { _ in CGFloat.random(in: 0.3...1) }
    }
}
