import SwiftUI

/// Shared app chrome theme: a dark charcoal base with a soft, blurred
/// multi-colour gradient wash (teal → indigo → warm) bleeding up through the
/// glass — the look used across Settings and onboarding.
enum AppTheme {
    /// Primary accent for buttons/highlights — follows the user's macOS accent
    /// colour (System Settings → Appearance → Colour), live-updating with it.
    static let accent = Color.accentColor
    /// Near-black base behind everything.
    static let base = Color(red: 0.055, green: 0.06, blue: 0.078)
}

/// A full-bleed themed backdrop: dark base with a few large, soft colour blobs.
struct ThemedBackground: View {
    var body: some View {
        ZStack {
            AppTheme.base

            // Soft colour blobs, heavily blurred, low opacity.
            Circle()
                .fill(AppTheme.accent.opacity(0.24))
                .frame(width: 520, height: 520)
                .blur(radius: 140)
                .offset(x: -240, y: -220)
            Circle()
                .fill(Color(red: 0.42, green: 0.32, blue: 0.85).opacity(0.28))
                .frame(width: 620, height: 620)
                .blur(radius: 160)
                .offset(x: 200, y: -40)
            Circle()
                .fill(Color(red: 0.72, green: 0.28, blue: 0.42).opacity(0.22))
                .frame(width: 560, height: 560)
                .blur(radius: 150)
                .offset(x: -140, y: 300)
        }
        .ignoresSafeArea()
    }
}
