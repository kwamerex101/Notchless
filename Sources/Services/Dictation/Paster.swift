import AppKit

/// Delivers finished dictation text into the frontmost app by placing it on the
/// pasteboard and simulating ⌘V. Restores the prior clipboard afterwards.
enum Paster {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulateCommandV()

        // Restore the user's clipboard shortly after the paste lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private static func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // "v"
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
