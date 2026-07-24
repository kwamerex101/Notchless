import SwiftUI

/// A small dot that gently pulses (scale + opacity), used for the privacy
/// camera/mic indicator and the meeting recording indicator. See
/// docs/flat-dark-spec.md §1 (PulsingDot) and §4 (Reduce Motion).
struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 8
    /// Delays the first pulse so a paired dot (e.g. camera + mic) alternates
    /// with its partner instead of pulsing in lockstep. The spec calls this
    /// out as "a second instance offset by -0.8s"; a positive start delay on
    /// a matching-duration repeat produces the same alternating phase.
    var phaseOffset: TimeInterval = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 1 : 0.6)
            .opacity(pulsing ? 1 : 0.45)
            .animation(
                reduceMotion
                    ? nil
                    : Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(phaseOffset),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
