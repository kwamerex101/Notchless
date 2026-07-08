import SwiftUI

@main
struct NotchlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notchless", systemImage: "rectangle.topthird.inset.filled") {
            Button("Start / Stop Dictation") { appDelegate.dictation.toggle() }
            Button("Camera Mirror") { appDelegate.model.toggleMirror() }
            Button("Settings…") { SettingsWindowController.shared.show(meeting: appDelegate.meeting) }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Notchless") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
