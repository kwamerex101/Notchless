import AppKit
import Combine

/// The modifier combo held to dictate. Combos (not single modifiers) avoid
/// clobbering normal Option/Command shortcuts — mirrors ListenToMe.
enum DictationHotkeyOption: String, CaseIterable, Identifiable {
    case controlOption
    case controlCommand
    case fnCommand
    case fnOption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOption: return "Control + Option"
        case .controlCommand: return "Control + Command"
        case .fnCommand: return "Fn + Command"
        case .fnOption: return "Fn + Option"
        }
    }

    /// The flags that must ALL be held for this combo.
    var requiredFlags: CGEventFlags {
        switch self {
        case .controlOption: return [.maskControl, .maskAlternate]
        case .controlCommand: return [.maskControl, .maskCommand]
        case .fnCommand: return [.maskSecondaryFn, .maskCommand]
        case .fnOption: return [.maskSecondaryFn, .maskAlternate]
        }
    }
}

/// Where a finished transcript goes.
enum DictationOutput: String, CaseIterable, Identifiable {
    case pasteActiveApp
    case clipboard
    case appleNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pasteActiveApp: return "Active app"
        case .clipboard: return "Clipboard"
        case .appleNotes: return "Apple Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .pasteActiveApp: return "arrow.down.doc"
        case .clipboard: return "doc.on.clipboard"
        case .appleNotes: return "note.text"
        }
    }
}

/// Whether/when to polish the raw transcript.
enum DictationCleanup: String, CaseIterable, Identifiable {
    case off
    case smart      // clean only longer transcripts
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Never"
        case .smart: return "Smart"
        case .always: return "Always"
        }
    }
}

/// All persisted dictation preferences. Self-contained (own UserDefaults keys)
/// so it doesn't bloat the main SettingsStore.
@MainActor
final class DictationSettings: ObservableObject {
    static let shared = DictationSettings()

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { persist(Keys.enabled, enabled) } }
    @Published var hotkey: DictationHotkeyOption { didSet { persist(Keys.hotkey, hotkey.rawValue) } }
    @Published var languageID: String { didSet { persist(Keys.language, languageID) } }
    @Published var microphoneUID: String { didSet { persist(Keys.mic, microphoneUID) } }
    @Published var output: DictationOutput { didSet { persist(Keys.output, output.rawValue) } }
    @Published var cleanup: DictationCleanup { didSet { persist(Keys.cleanup, cleanup.rawValue) } }
    @Published var autoCapitalize: Bool { didSet { persist(Keys.autoCap, autoCapitalize) } }
    @Published var historyRetentionDays: Int { didSet { persist(Keys.retention, historyRetentionDays) } }
    @Published var maxRecordingSeconds: Int { didSet { persist(Keys.maxDuration, maxRecordingSeconds) } }
    @Published var soundCues: Bool { didSet { persist(Keys.soundCues, soundCues) } }
    @Published var voiceCommands: Bool { didSet { persist(Keys.voiceCommands, voiceCommands) } }
    @Published var encryptHistory: Bool { didSet { persist(Keys.encrypt, encryptHistory); DictationHistory.shared.reencrypt(encrypted: encryptHistory) } }

    init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.hotkey: DictationHotkeyOption.controlOption.rawValue,
            Keys.language: Locale.current.identifier,
            Keys.mic: "",
            Keys.output: DictationOutput.pasteActiveApp.rawValue,
            Keys.cleanup: DictationCleanup.off.rawValue,
            Keys.autoCap: true,
            Keys.retention: 30,
            Keys.maxDuration: 120,
            Keys.soundCues: true,
            Keys.voiceCommands: false,
            Keys.encrypt: false,
        ])
        enabled = defaults.bool(forKey: Keys.enabled)
        hotkey = DictationHotkeyOption(rawValue: defaults.string(forKey: Keys.hotkey) ?? "") ?? .controlOption
        languageID = defaults.string(forKey: Keys.language) ?? Locale.current.identifier
        microphoneUID = defaults.string(forKey: Keys.mic) ?? ""
        output = DictationOutput(rawValue: defaults.string(forKey: Keys.output) ?? "") ?? .pasteActiveApp
        cleanup = DictationCleanup(rawValue: defaults.string(forKey: Keys.cleanup) ?? "") ?? .off
        autoCapitalize = defaults.bool(forKey: Keys.autoCap)
        historyRetentionDays = defaults.integer(forKey: Keys.retention)
        maxRecordingSeconds = defaults.integer(forKey: Keys.maxDuration)
        soundCues = defaults.bool(forKey: Keys.soundCues)
        voiceCommands = defaults.bool(forKey: Keys.voiceCommands)
        encryptHistory = defaults.bool(forKey: Keys.encrypt)
    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let enabled = "dictation.enabled"
        static let hotkey = "dictation.hotkey"
        static let language = "dictation.language"
        static let mic = "dictation.mic"
        static let output = "dictation.output"
        static let cleanup = "dictation.cleanup"
        static let autoCap = "dictation.autoCapitalize"
        static let retention = "dictation.retentionDays"
        static let maxDuration = "dictation.maxDurationSeconds"
        static let soundCues = "dictation.soundCues"
        static let voiceCommands = "dictation.voiceCommands"
        static let encrypt = "dictation.encryptHistory"
    }
}
