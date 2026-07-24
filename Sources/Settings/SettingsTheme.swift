import SwiftUI

/// Shared flat-dark design tokens for the Settings window — colours only,
/// no layout. See `docs/flat-dark-spec.md` §5.
enum SettingsTheme {
    // Chrome
    static let windowBody = Color(hex: 0x1B_1D_24)
    static let sidebar = Color(hex: 0x14_16_1C)
    static let sidebarBorder = Color.white.opacity(0.06)
    static let windowBorder = Color.white.opacity(0.1)

    // Surfaces
    static let card = Color.white.opacity(0.05)
    static let cardDivider = Color.white.opacity(0.07)
    static let controlChip = Color.white.opacity(0.08)
    static let button = Color.white.opacity(0.09)
    static let insetField = Color.white.opacity(0.07)
    static let iconChip = Color.white.opacity(0.08)
    static let sidebarSelected = Color.white.opacity(0.10)

    // Switch
    static let switchOn = Color(hex: 0x30_D1_58)
    static let switchOff = Color.white.opacity(0.14)
    static let switchKnobOn = Color.white
    static let switchKnobOff = Color.white.opacity(0.85)

    // Destructive
    static let destructiveBg = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255).opacity(0.14)
    static let destructiveText = Color(hex: 0xFF_69_61)

    // Primary
    static let primaryFill = Color(hex: 0xF2_F3_F5)
    static let onPrimary = Color(hex: 0x17_1A_22)

    // Text
    static let text = Color(hex: 0xF2_F3_F5)
    static let textSecondary = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.55)
    static let textTertiary = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.45)
    static let textMuted = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.62)
    static let textPlaceholder = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.4)
    static let sidebarHeader = Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.5)

    // Status
    static let statusGranted = Color(hex: 0x30_D1_58)
    static let statusDenied = Color(hex: 0xFF_45_3A)
    static let statusUnset = Color.white.opacity(0.3)
}
