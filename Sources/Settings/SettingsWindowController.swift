import AppKit
import SwiftUI

/// Owns the Settings window (a normal titled window, unlike the notch panel).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(meeting: MeetingController) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: .shared, meeting: meeting))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Notchless Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // Flat-dark is a dark-only design (docs/flat-dark-spec.md §5) — force
        // .darkAqua rather than following the system light/dark appearance.
        // Traffic lights sit inside the dark sidebar, so the titlebar is
        // transparent and its title hidden; the sidebar draws its own
        // top padding to make room for them (spec §5 sidebar).
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 880, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
