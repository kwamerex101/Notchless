import CoreGraphics

/// A fixed-capacity rolling buffer of amplitude samples (0…1) for the scrolling
/// dictation waveform. Newest sample lands on the right; the oldest falls off
/// the left. Silence renders as `floor`, not zero, so the trace never fully
/// flatlines. Pure value type — no SwiftUI, fully unit-testable.
struct WaveformBuffer {
    let capacity: Int
    let floor: CGFloat
    private(set) var samples: [CGFloat]

    init(capacity: Int = 48, floor: CGFloat = 0.04) {
        self.capacity = max(1, capacity)
        self.floor = floor
        self.samples = Array(repeating: floor, count: self.capacity)
    }

    /// Append a new sample on the right, dropping the oldest on the left.
    mutating func push(_ level: CGFloat) {
        let clamped = min(1, max(0, level))
        samples.removeFirst()
        samples.append(clamped)
    }

    /// Return every sample to the silence floor.
    mutating func reset() {
        samples = Array(repeating: floor, count: capacity)
    }
}
