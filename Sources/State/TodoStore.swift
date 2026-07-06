import SwiftUI

/// A checkable sub-item of a `Todo`. Pure data.
struct Subtask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// A single task in the notch checklist: title + done state, plus an optional
/// ordered list of subtasks and a free-text notes field.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var subtasks: [Subtask]
    var notes: String

    init(id: UUID = UUID(), title: String, isDone: Bool = false,
         createdAt: Date = Date(), subtasks: [Subtask] = [], notes: String = "") {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.subtasks = subtasks
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isDone, createdAt, subtasks, notes
    }

    // Custom decode so v1 JSON (no `subtasks`/`notes`) still loads — existing
    // saved tasks must not be lost. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// (completed, total) subtasks — drives the "2/5" progress badge.
    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// True when there's non-whitespace note text (drives the note/link glyph).
    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True only when there is at least one subtask and all are done — the
    /// trigger for hybrid auto-complete.
    var allSubtasksDone: Bool {
        !subtasks.isEmpty && subtasks.allSatisfy(\.isDone)
    }
}

/// The slice of `NSUbiquitousKeyValueStore` that `TodoStore` depends on.
/// Abstracted so tests can inject a fake cloud without touching real iCloud.
protocol CloudKeyValueStore: AnyObject {
    func data(forKey aKey: String) -> Data?
    func set(_ aData: Data?, forKey aKey: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}

/// Holds the notch task list. Mirrors `FileTrayStore` (a dedicated store, not
/// `SettingsStore`), but persists to `UserDefaults` as JSON and syncs two-way
/// with iCloud when the user's sync pref is on: `persist()` mirrors outbound,
/// while inbound changes from another Mac (delivered via
/// `NSUbiquitousKeyValueStore.didChangeExternallyNotification`) are pulled back
/// into `defaults` and republished so the notch updates live. Both the Settings
/// pane and the notch read/write the `.shared` instance, so edits stay in sync.
@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    static let storageKey = "todoItems"

    @Published private(set) var items: [Todo] = []

    var isEmpty: Bool { items.isEmpty }
    /// The task the compact cue shows: the first still-open one (skips a task
    /// that's mid-strike-through after being checked off).
    var next: Todo? { items.first { !$0.isDone } }
    var openCount: Int { items.lazy.filter { !$0.isDone }.count }

    private let defaults: UserDefaults
    private let cloud: CloudKeyValueStore?
    private let removalDelay: TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var cloudObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        cloud: CloudKeyValueStore? = NSUbiquitousKeyValueStore.default,
        removalDelay: TimeInterval = 0.9,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.removalDelay = removalDelay
        self.schedule = schedule
        seedDefaultsFromCloud()
        load()
        observeCloud()
    }

    deinit {
        if let cloudObserver { NotificationCenter.default.removeObserver(cloudObserver) }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(Todo(title: trimmed))
        persist()
    }

    /// Marks a task done (drives the strike-through), then removes it after
    /// `removalDelay` so it briefly shows completed before vanishing.
    func complete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].isDone else { return }
        items[i].isDone = true
        persist()
        schedule(removalDelay) { [weak self] in self?.remove(id) }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func updateTitle(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = trimmed
        persist()
    }

    func addSubtask(to parentID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.append(Subtask(title: trimmed))
        persist()
    }

    /// Flips a subtask's done state (it stays in the list, struck through). If
    /// that leaves every subtask done, the parent auto-completes (hybrid rule):
    /// `complete` runs its strike-through-then-vanish, taking the subtasks along.
    func toggleSubtask(_ subtaskID: UUID, in parentID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == parentID }),
              let j = items[i].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        items[i].subtasks[j].isDone.toggle()
        persist()
        if items[i].allSubtasksDone { complete(parentID) }
    }

    func updateSubtaskTitle(_ subtaskID: UUID, in parentID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = items.firstIndex(where: { $0.id == parentID }),
              let j = items[i].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        items[i].subtasks[j].title = trimmed
        persist()
    }

    func removeSubtask(_ subtaskID: UUID, from parentID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.removeAll { $0.id == subtaskID }
        persist()
    }

    func moveSubtask(in parentID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func updateNotes(of parentID: UUID, to notes: String) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].notes = notes
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            // Codable Todo (UUID/String/Bool/Date) can't realistically fail to
            // encode; if it somehow does, surface it rather than silently
            // dropping the write.
            assertionFailure("Failed to encode todos: \(error)")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
        if let cloud, SettingsStore.shared.syncViaICloud {
            cloud.set(data, forKey: Self.storageKey)
            cloud.synchronize()
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Todo].self, from: data)
        else {
            items = []
            return
        }
        items = decoded
    }

    /// If iCloud sync is on and the cloud store already holds a task list, copy
    /// it into `defaults` so the following `load()` picks it up. Lets a second
    /// Mac inherit the list on first launch and after every external change.
    private func seedDefaultsFromCloud() {
        guard let cloud, SettingsStore.shared.syncViaICloud,
              let data = cloud.data(forKey: Self.storageKey)
        else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Register for inbound iCloud changes (writes from another Mac). The
    /// notification is delivered off the main thread, and its block hops back
    /// onto the main actor before touching published state.
    private func observeCloud() {
        guard let cloud else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cloudChanged() }
        }
    }

    /// An external iCloud change arrived: pull the cloud's copy into `defaults`,
    /// re-`load()`, and republish so the notch and Settings update live.
    /// Mirrors `SettingsStore.cloudChanged`.
    private func cloudChanged() {
        guard SettingsStore.shared.syncViaICloud else { return }
        seedDefaultsFromCloud()
        load()
    }
}
