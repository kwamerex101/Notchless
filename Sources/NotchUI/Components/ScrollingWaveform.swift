import SwiftUI

/// A scrolling, symmetric, edge-faded voice waveform. A ~30 Hz tick pushes the
/// current input level onto a rolling buffer so the trace scrolls left even
/// through silence (settling to a low floor). Bars mirror about the horizontal
/// center. Under Reduce Motion it renders a static, flat trace with no ticking.
struct ScrollingWaveform: View {
    var level: CGFloat
    var isRecording: Bool
    var reduceMotion: Bool

    private let barCount = 48
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 24
    private let floor: CGFloat = 0.04

    @State private var buffer = WaveformBuffer(capacity: 48, floor: 0.04)
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let step = barWidth + barSpacing
            for (i, sample) in buffer.samples.enumerated() {
                let x = CGFloat(i) * step
                let h = max(floor, sample) * maxHeight
                let rect = CGRect(x: x, y: mid - h / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                         with: .color(.white.opacity(0.9)))
            }
        }
        .frame(height: maxHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .mask(edgeFade)
        .onAppear { buffer.reset() }
        .onChange(of: isRecording) { _, recording in if recording { buffer.reset() } }
        .onReceive(tick) { _ in
            guard isRecording, !reduceMotion else { return }
            buffer.push(level)
        }
    }

    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.88),
            .init(color: .clear, location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
