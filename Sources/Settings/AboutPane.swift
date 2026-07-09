import SwiftUI

struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Notchless").font(.title3.bold())
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
            }
            Text("Notchless turns your Mac's notch into a Dynamic Island.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Run setup again") { OnboardingWindowController.shared.rerun() }
            Divider().padding(.vertical, 4)
            Text("Uninstall").font(.headline)
            Text("Removes downloaded data, history, dictionary, snippets, settings, and moves Notchless to the Trash.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Uninstall & delete all data", role: .destructive) { Uninstaller.uninstall() }
            Spacer()
        }
    }
}
