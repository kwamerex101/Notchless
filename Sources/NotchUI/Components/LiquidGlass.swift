import SwiftUI

/// User-selectable Liquid Glass look (System-Settings-style Clear vs Tinted).
enum GlassStyle: String, CaseIterable, Identifiable, Codable {
    case clear
    case tinted
    var id: String { rawValue }
    var title: String { self == .clear ? "Clear" : "Tinted" }
}

/// A glass surface whose look follows the app's glass settings (Clear/Tinted +
/// intensity). Observing `SettingsStore.shared` means every glass surface —
/// notch and Settings — updates live when the user changes the option.
struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool
    var fallback: Material

    @ObservedObject private var settings = SettingsStore.shared

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(resolvedGlass(), in: shape)
        } else {
            content
                .background(fallbackMaterial, in: shape)
                .overlay(shape.fill((tint ?? AppTheme.accent).opacity(tintOpacity * 0.5)))
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    /// Intensity scales the tint strength; Tinted also gets a stronger floor.
    private var tintOpacity: Double {
        let intensity = min(1, max(0, settings.glassIntensity))
        return settings.glassStyle == .tinted ? 0.12 + intensity * 0.35 : intensity * 0.18
    }

    private var fallbackMaterial: Material {
        settings.glassStyle == .clear ? .ultraThinMaterial : fallback
    }

    @available(macOS 26.0, *)
    private func resolvedGlass() -> Glass {
        var glass: Glass = settings.glassStyle == .clear ? .clear : .regular
        // Explicit tints (e.g. prominent accents) win; otherwise Tinted washes
        // the glass with the accent colour at the chosen intensity.
        if let tint {
            glass = glass.tint(tint.opacity(tintOpacity + 0.3))
        } else if settings.glassStyle == .tinted {
            glass = glass.tint(AppTheme.accent.opacity(tintOpacity))
        }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Liquid Glass helpers. On macOS 26+ these use the real `glassEffect` /
/// `.glass` button styles; on macOS 14–15 they fall back to Materials. The look
/// (Clear/Tinted + intensity) is driven by the user's settings.
extension View {
    /// Applies Liquid Glass in `shape`, following the app's glass settings.
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback material: Material = .regularMaterial
    ) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive, fallback: material))
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
