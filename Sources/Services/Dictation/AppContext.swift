import AppKit

/// Identifies the app that will receive the dictation, so cleanup can adapt its
/// tone (e.g. preserve code identifiers in an editor). Pure AppKit — reads the
/// frontmost application only; never its contents.
enum AppCategory: String, Codable {
    case codeEditor
    case terminal
    case browser
    case messaging
    case notes
    case other

    /// A cleanup-prompt hint tuned to this destination.
    var promptHint: String {
        switch self {
        case .codeEditor, .terminal:
            return "This text goes into code. Preserve identifiers, camelCase, snake_case, and symbols exactly; do not capitalize or punctuate code tokens."
        case .messaging:
            return "This is a casual message. Keep it conversational; don't over-formalize."
        case .notes:
            return "This is a personal note. Light structural cleanup only."
        case .browser, .other:
            return ""
        }
    }
}

struct AppContext {
    let bundleID: String
    let category: AppCategory

    /// Captures the current frontmost app. Call on the main actor.
    @MainActor
    static func current() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? ""
        return AppContext(bundleID: bundleID, category: category(for: bundleID))
    }

    private static func category(for bundleID: String) -> AppCategory {
        let id = bundleID.lowercased()
        let codeEditors = ["com.microsoft.vscode", "com.apple.dt.xcode", "com.jetbrains",
                           "com.sublimetext", "dev.zed", "com.todesktop", "com.github.atom",
                           "com.panic.nova", "com.googlecode.iterm2.cursor", "com.cursor"]
        let terminals = ["com.apple.terminal", "com.googlecode.iterm2", "dev.warp", "net.kovidgoyal.kitty",
                         "com.github.wez.wezterm", "io.alacritty"]
        let browsers = ["com.apple.safari", "com.google.chrome", "org.mozilla.firefox",
                        "company.thebrowser.browser", "com.microsoft.edgemac", "com.brave.browser"]
        let messaging = ["com.apple.ichat", "com.apple.messages", "com.tinyspeck.slackmacgap",
                         "com.hnc.discord", "com.microsoft.teams", "net.whatsapp.whatsapp",
                         "org.telegram.desktop"]
        let notes = ["com.apple.notes", "notion.id", "md.obsidian", "com.agiletortoise.drafts-mac",
                     "com.bear-writer"]

        if codeEditors.contains(where: id.contains) { return .codeEditor }
        if terminals.contains(where: id.contains) { return .terminal }
        if browsers.contains(where: id.contains) { return .browser }
        if messaging.contains(where: id.contains) { return .messaging }
        if notes.contains(where: id.contains) { return .notes }
        return .other
    }
}
