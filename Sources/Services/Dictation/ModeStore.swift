import Foundation

/// Persists dictation modes and resolves the active one. Modes are stored as
/// JSON in UserDefaults; the built-ins seed once (tracked by `didSeed`) so a
/// deleted built-in doesn't reappear. `pinnedModeID` (nil = Auto) wins over
/// app-binding, which wins over the always-present Default mode.
@MainActor
final class ModeStore: ObservableObject {
    static let shared = ModeStore()

    @Published private(set) var modes: [Mode] = []
    @Published var pinnedModeID: UUID? { didSet { persistPin() } }

    private let defaults: UserDefaults
    private enum Keys {
        static let modes = "dictation.modes"
        static let pin = "dictation.modes.pinned"
        static let didSeed = "dictation.modes.didSeed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Keys.didSeed), let data = defaults.data(forKey: Keys.modes),
           let saved = try? JSONDecoder().decode([Mode].self, from: data) {
            modes = saved
        } else {
            modes = Mode.builtIns()
            defaults.set(true, forKey: Keys.didSeed)
            persistModes()
        }
        // The Default mode must always exist.
        if !modes.contains(where: { $0.id == Mode.defaultID }) {
            modes.insert(Mode.builtIns()[0], at: 0)
            persistModes()
        }
        if let s = defaults.string(forKey: Keys.pin), let id = UUID(uuidString: s) { pinnedModeID = id }
    }

    // MARK: Resolution

    func resolve(forBundleID bundleID: String?) -> Mode {
        Self.resolve(modes: modes, pinnedModeID: pinnedModeID, defaultID: Mode.defaultID, bundleID: bundleID)
    }

    /// Pure resolution: pinned(enabled) → app-binding(enabled) → default.
    static func resolve(modes: [Mode], pinnedModeID: UUID?, defaultID: UUID, bundleID: String?) -> Mode {
        let byID = Dictionary(modes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fallback = byID[defaultID] ?? modes.first ?? Mode(id: defaultID, name: "Default", systemImage: "mic")
        if let pinnedModeID, let pinned = byID[pinnedModeID], pinned.isEnabled { return pinned }
        if let bundleID,
           let bound = modes.first(where: { $0.isEnabled && $0.boundBundleIDs.contains(bundleID) }) {
            return bound
        }
        return fallback
    }

    // MARK: CRUD

    var enabledModes: [Mode] { modes.filter(\.isEnabled) }

    func add(_ mode: Mode) { modes.append(mode); persistModes() }

    func update(_ mode: Mode) {
        guard let i = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        modes[i] = mode; persistModes()
    }

    /// Insert the mode if new, else replace the existing one. Used by the editor's Done.
    func save(_ mode: Mode) {
        if let i = modes.firstIndex(where: { $0.id == mode.id }) { modes[i] = mode } else { modes.append(mode) }
        persistModes()
    }

    func delete(_ mode: Mode) {
        guard mode.id != Mode.defaultID else { return }   // Default is undeletable
        modes.removeAll { $0.id == mode.id }
        if pinnedModeID == mode.id { pinnedModeID = nil }
        persistModes()
    }

    func move(from source: IndexSet, to destination: Int) {
        modes.move(fromOffsets: source, toOffset: destination); persistModes()
    }

    // MARK: Persistence

    private func persistModes() {
        if let data = try? JSONEncoder().encode(modes) { defaults.set(data, forKey: Keys.modes) }
    }
    private func persistPin() {
        defaults.set(pinnedModeID?.uuidString, forKey: Keys.pin)
    }
}
