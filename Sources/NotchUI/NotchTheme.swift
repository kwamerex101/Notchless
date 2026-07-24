import SwiftUI

/// User-selectable surface tint applied behind every notch state.
/// See `docs/flat-dark-spec.md` §1.
enum NotchTint: String, CaseIterable, Identifiable, Codable {
    case graphite
    case blue
    case purple
    case green
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .green: return "Green"
        case .black: return "Black"
        }
    }

    var color: Color {
        switch self {
        case .graphite: return Color(hex: 0x17_1A_22)
        case .blue: return Color(hex: 0x14_1B_2E)
        case .purple: return Color(hex: 0x1D_15_30)
        case .green: return Color(hex: 0x12_20_19)
        case .black: return Color(hex: 0x0B_0B_0E)
        }
    }
}

/// Shared flat-dark design tokens for the notch surface — colours only,
/// no layout. See `docs/flat-dark-spec.md` §1.
enum NotchTheme {
    // Surface
    static let hairline = Color.white.opacity(0.08)
    static let hairlineWidth: CGFloat = 0.5

    // Text
    static let textPrimary = Color(hex: 0xF2_F3_F5)
    static let textSecondary = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.55)
    static let textTertiary = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.45)
    static let textBrightSecondary = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.75)

    // Fills
    static let track = Color.white.opacity(0.16)
    static let fill = Color.white
    static let chip = Color.white.opacity(0.09)
    static let inset = Color.white.opacity(0.06)
    static let artworkPlaceholder = Color(hex: 0x3A_3D_45)
    static let ringTrack = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.10)

    // Semantic
    static let positive = Color(hex: 0x30_D1_58)
    static let recording = Color(hex: 0xFF_45_3A)
    static let destructiveText = Color(hex: 0xFF_69_61)
    static let warning = Color(hex: 0xFF_9F_0A)
    static let link = Color(hex: 0x0A_84_FF)
    static let focus = Color(hex: 0xBF_5A_F2)
}

extension Color {
    /// Builds an opaque colour from a 24-bit hex literal, e.g. `Color(hex: 0x171A22)`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
