import Foundation

/// A named dictation preset. Every override field is optional — `nil` means
/// "inherit the global DictationSettings value". `instruction` augments (does
/// not replace) the intensity-based cleanup prompt.
struct Mode: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var systemImage: String
    var isEnabled: Bool = true
    var isBuiltIn: Bool = false
    var boundBundleIDs: [String] = []

    var instruction: String? = nil
    var cleanup: DictationCleanup? = nil
    var cleanupIntensity: DictationCleanupIntensity? = nil
    var output: DictationOutput? = nil
    var voiceCommands: Bool? = nil
    var smartFormatting: Bool? = nil
    var autoCapitalize: Bool? = nil
    var engine: DictationEngine? = nil
    var languageID: String? = nil
    var hotkey: DictationHotkeyOption? = nil

    /// The always-present fallback mode's stable id.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-0000000000DE")!

    /// Overlay this mode's non-nil overrides onto a base (the global config).
    func applied(over base: EffectiveDictation) -> EffectiveDictation {
        EffectiveDictation(
            output: output ?? base.output,
            cleanup: cleanup ?? base.cleanup,
            cleanupIntensity: cleanupIntensity ?? base.cleanupIntensity,
            voiceCommands: voiceCommands ?? base.voiceCommands,
            smartFormatting: smartFormatting ?? base.smartFormatting,
            autoCapitalize: autoCapitalize ?? base.autoCapitalize,
            engine: engine ?? base.engine,
            languageID: languageID ?? base.languageID,
            instruction: instruction
        )
    }

    /// The seeded built-ins. Fixed ids so re-seeding/updates are stable.
    static func builtIns() -> [Mode] {
        [
            Mode(id: defaultID, name: "Default", systemImage: "mic", isBuiltIn: true),
            {
                var m = Mode(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
                             name: "Email", systemImage: "envelope", isBuiltIn: true)
                m.instruction = "Rewrite as a clear, professional email — fix grammar and structure, keep my meaning and any greeting or sign-off."
                m.cleanup = .always; m.cleanupIntensity = .medium
                return m
            }(),
            {
                var m = Mode(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
                             name: "Code", systemImage: "chevron.left.forwardslash.chevron.right", isBuiltIn: true)
                m.instruction = "This is code or technical text. Preserve identifiers, camelCase/snake_case, and symbols exactly. Do not add prose or punctuation to tokens."
                m.cleanup = .smart; m.cleanupIntensity = .light; m.smartFormatting = true
                return m
            }(),
            {
                var m = Mode(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E3")!,
                             name: "Notes", systemImage: "note.text", isBuiltIn: true)
                m.instruction = "Light cleanup for a personal note — structural only, keep it casual."
                m.output = .appleNotes; m.cleanup = .smart
                return m
            }(),
            {
                var m = Mode(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E4")!,
                             name: "Casual", systemImage: "bubble.left", isBuiltIn: true)
                m.instruction = "Keep it conversational and informal; light punctuation only."
                m.cleanup = .smart; m.cleanupIntensity = .light
                return m
            }(),
        ]
    }
}

/// Modifier combos a mode may claim for its dedicated hotkey: all combos except
/// the main dictation hotkey and combos already taken by other ENABLED modes.
/// A mode's own current hotkey stays selectable.
func availableHotkeys(for mode: Mode, main: DictationHotkeyOption, modes: [Mode]) -> [DictationHotkeyOption] {
    let takenByOthers = Set(modes.filter { $0.id != mode.id && $0.isEnabled }.compactMap(\.hotkey))
    return DictationHotkeyOption.allCases.filter { $0 != main && !takenByOthers.contains($0) }
}

/// The resolved per-session dictation config after a mode is applied.
struct EffectiveDictation: Equatable {
    var output: DictationOutput
    var cleanup: DictationCleanup
    var cleanupIntensity: DictationCleanupIntensity
    var voiceCommands: Bool
    var smartFormatting: Bool
    var autoCapitalize: Bool
    var engine: DictationEngine
    var languageID: String
    var instruction: String?
}
