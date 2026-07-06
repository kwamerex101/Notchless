import SwiftUI

/// Shared button feel for in-notch controls: brighten + slightly grow on hover,
/// dim + shrink on press. Layout-neutral (no padding/background changes), so it
/// can drop onto any existing icon button without shifting the row.
struct NotchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : (hovering ? 1 : 0.9))
                .scaleEffect(scale)
                .animation(NotchMotion.animation(NotchMotion.micro, reduceMotion: reduceMotion), value: hovering)
                .animation(NotchMotion.animation(NotchMotion.micro, reduceMotion: reduceMotion), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var scale: CGFloat {
            if reduceMotion { return 1 }
            if configuration.isPressed { return 0.88 }
            return hovering ? 1.08 : 1
        }
    }
}
