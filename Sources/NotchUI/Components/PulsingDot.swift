import SwiftUI

/// A small dot that gently pulses (scale + opacity), used for the privacy
/// camera/mic indicator.
struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulsing ? 1 : 0.55)
            .opacity(pulsing ? 1 : 0.45)
            .shadow(color: color.opacity(0.7), radius: pulsing ? 4 : 0)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
