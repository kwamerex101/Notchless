import SwiftUI

/// Shared app accent used for buttons and glass tints.
enum AppTheme {
    /// Primary accent for buttons/highlights — follows the user's macOS accent
    /// colour (System Settings → Appearance → Colour), live-updating with it.
    static let accent = Color.accentColor
}
