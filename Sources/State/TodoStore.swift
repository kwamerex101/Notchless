import SwiftUI

/// A single task in the notch checklist. Pure data — title + done state.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

/// Holds the notch task list. Mirrors `FileTrayStore` (a dedicated store, not
/// `SettingsStore`), but persists to `UserDefaults` as JSON and mirrors to
/// iCloud when the user's sync pref is on. Both the Settings pane and the notch
/// read/write the `.shared` instance, so edits stay in sync.
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
    private let cloud: NSUbiquitousKeyValueStore?
    private let removalDelay: TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default,
        removalDelay: TimeInterval = 0.9,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.removalDelay = removalDelay
        self.schedule = schedule
        load()
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

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
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
}
