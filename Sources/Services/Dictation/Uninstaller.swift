import AppKit

/// Removes Notchless's stored data and moves the app to the Trash.
enum Uninstaller {
    static func uninstall() {
        // App-support data (history, etc.).
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchless", isDirectory: true)
        try? FileManager.default.removeItem(at: support)

        // Preferences.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Move the app bundle to the Trash, then quit.
        let appURL = Bundle.main.bundleURL
        try? FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
        NSApp.terminate(nil)
    }
}
