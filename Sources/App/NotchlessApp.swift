import SwiftUI

@main
struct NotchlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// `--dump-states [dir]`: render every notch state and settings pane to
    /// PNGs and quit, before the notch panel, menu bar item, or any service
    /// spins up. Runs ahead of the normal SwiftUI launch (`App.main()` builds
    /// `Self()` before calling into the run loop), so `exit(0)` here means
    /// `applicationDidFinishLaunching` never fires.
    init() {
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--dump-states") {
            let dirArg = args.indices.contains(flagIndex + 1) ? args[flagIndex + 1] : "./state-dump"
            let outputDirectory = URL(fileURLWithPath: dirArg)
            DebugStateDump.run(outputDirectory: outputDirectory)
            exit(0)
        }
    }

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
