import SwiftUI

/// Version, credits, and the setup/uninstall actions. See spec §5 "ABOUT".
struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsTheme.iconChip)
                        .frame(width: 38, height: 38)
                    // A miniature notch mark — the app's own glyph, not a
                    // system symbol, to match the spec's icon-chip mockup.
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 3.5, bottomTrailing: 3.5, topTrailing: 0),
                        style: .continuous
                    )
                    .fill(SettingsTheme.text)
                    .frame(width: 20, height: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notchless").font(.system(size: 14, weight: .bold)).foregroundStyle(SettingsTheme.text)
                    Text("Version \(version)").font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                }
            }

            Footnote("Notchless turns your Mac's notch into a Dynamic Island.")

            HStack(spacing: 8) {
                FlatButton(title: "Run setup again") { OnboardingWindowController.shared.rerun() }
                FlatButton(title: "Uninstall & delete all data", style: .destructive) { Uninstaller.uninstall() }
            }

            Footnote("Removes downloaded data, history, dictionary, snippets, settings, and moves Notchless to the Trash.")
        }
    }
}
