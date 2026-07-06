import SwiftUI

/// Builds a `Glass` value (macOS 26+ only) from tint/interactive options.
@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// Liquid Glass helpers. On macOS 26+ these use the real `glassEffect` /
/// `.glass` button styles; on macOS 14–15 they fall back to Materials so the
/// app still builds and looks reasonable. Centralised so the SDK-27 transition
/// (and any tuning) happens in one place.
extension View {
    /// Applies Liquid Glass in `shape` on macOS 26+, else a material fill.
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback material: Material = .regularMaterial
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(material, in: shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    /// Prominent glass button style on macOS 26+, `.borderedProminent` below.
    @ViewBuilder
    func liquidGlassProminentButton(tint: Color = .accentColor) -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(tint)
        } else {
            self.buttonStyle(.borderedProminent).tint(tint)
        }
    }
}
