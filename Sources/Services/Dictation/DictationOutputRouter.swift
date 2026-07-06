import AppKit

/// Delivers a finished transcript to the chosen destination.
enum DictationOutputRouter {
    static func deliver(_ text: String, to output: DictationOutput) {
        switch output {
        case .pasteActiveApp:
            Paster.paste(text)
        case .clipboard:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .appleNotes:
            appendToNotes(text)
        }
    }

    /// Appends a timestamped paragraph to a "Notchless" note via AppleScript.
    /// Triggers the one-time Automation prompt for Notes on first use.
    private static func appendToNotes(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
            if not (exists note "Notchless") then
                make new note with properties {name:"Notchless"}
            end if
            set theNote to note "Notchless"
            set body of theNote to (body of theNote) & "<div>" & "\(escaped)" & "</div>"
        end tell
        """
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
}
