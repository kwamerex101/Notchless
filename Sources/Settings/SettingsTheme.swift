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
    // Same red as `statusDenied` — bound to it so a future tweak can't desync.
    static let destructiveBg = statusDenied.opacity(0.14)
    static let destructiveText = Color(hex: 0xFF_69_61)

    // Primary
    static let primaryFill = Color(hex: 0xF2_F3_F5)
    static let onPrimary = Color(hex: 0x17_1A_22)

    // Text
    static let text = Color(hex: 0xF2_F3_F5)
    static let textSecondary = Color(hex: 0xEB_EE_F5).opacity(0.55)
    static let textTertiary = Color(hex: 0xEB_EE_F5).opacity(0.45)
    static let textMuted = Color(hex: 0xEB_EE_F5).opacity(0.62)
    static let textPlaceholder = Color(hex: 0xEB_EE_F5).opacity(0.4)
    static let sidebarHeader = Color(hex: 0xEB_EE_F5).opacity(0.5)
    /// Menu-picker value text (spec §5 "Menu picker") — brighter than `textSecondary`.
    static let menuValue = Color(hex: 0xEB_EE_F5).opacity(0.8)
    /// Selected notch-tint swatch caption (spec §5 "New control — Theme").
    static let swatchCaptionSelected = Color(hex: 0xEB_EE_F5).opacity(0.7)

    // Status
    static let statusGranted = Color(hex: 0x30_D1_58)
    static let statusDenied = Color(hex: 0xFF_45_3A)
    static let statusUnset = Color.white.opacity(0.3)

    // Swatch
    /// Inner hairline border on a notch-tint swatch (spec §5 "New control — Theme").
    static let swatchBorder = Color.white.opacity(0.2)
}
