import XCTest
import Combine
@testable import Notchless

/// In-memory stand-in for `NSUbiquitousKeyValueStore`, so the two-way iCloud
/// sync path can be exercised without a real iCloud account.
private final class FakeCloud: CloudKeyValueStore {
    var storage: [String: Data] = [:]
    func data(forKey aKey: String) -> Data? { storage[aKey] }
    func set(_ aData: Data?, forKey aKey: String) { storage[aKey] = aData }
    @discardableResult func synchronize() -> Bool { true }
}

@MainActor
final class TodoStoreTests: XCTestCase {
    /// A store backed by an ephemeral suite, no iCloud, and an immediate
    /// scheduler so completion removal happens synchronously in tests.
    private func makeStore(
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { _, work in work() }
    ) -> TodoStore {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        return TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: schedule)
    }

    func test_add_appendsTrimmedTask() {
        let store = makeStore()
        store.add("  Ship v1.1  ")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Ship v1.1")
    }

    func test_add_rejectsEmptyOrWhitespace() {
        let store = makeStore()
        store.add("")
        store.add("   \n ")
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_complete_removesTaskViaScheduler() {
        let store = makeStore() // immediate scheduler + delay 0 → removed synchronously
        store.add("A")
        store.complete(store.items[0].id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_next_skipsDoneTaskDuringStrikeThrough() {
        // Scheduler that never fires, so the completed task lingers (the
        // strike-through window). `next` must skip it.
        let store = makeStore(schedule: { _, _ in })
        store.add("A")
        store.add("B")
        store.complete(store.items[0].id)
        XCTAssertTrue(store.items[0].isDone)
        XCTAssertEqual(store.next?.title, "B")
    }

    func test_move_reorders() {
        let store = makeStore()
        store.add("A"); store.add("B"); store.add("C")
        store.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.items.map(\.title), ["C", "A", "B"])
    }

    func test_updateTitle_changesTitleAndRejectsEmpty() {
        let store = makeStore()
        store.add("old")
        let id = store.items[0].id
        store.updateTitle(id, to: "  new  ")
        XCTAssertEqual(store.items.first?.title, "new")
        store.updateTitle(id, to: "   ")
        XCTAssertEqual(store.items.first?.title, "new") // unchanged
    }

    func test_clear_removesAll() {
        let store = makeStore()
        store.add("A"); store.add("B")
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_persistence_roundTrips() {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        let s1 = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        s1.add("Persist me")
        let s2 = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        XCTAssertEqual(s2.items.map(\.title), ["Persist me"])
    }

    func test_load_recoversFromCorruptData() {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        suite.set(Data("not json".utf8), forKey: TodoStore.storageKey)
        let store = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Two-way iCloud sync

    /// A store wired to a fresh ephemeral suite and the given fake cloud, with
    /// the sync pref forced on so the cloud paths are exercised.
    private func makeSyncedStore(cloud: FakeCloud) -> TodoStore {
        SettingsStore.shared.syncViaICloud = true
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        return TodoStore(defaults: suite, cloud: cloud, removalDelay: 0, schedule: { _, w in w() })
    }

    func test_init_seedsItemsFromCloud() {
        // Cloud already holds a list (as if written by another Mac) but the
        // local defaults are empty — the store should adopt the cloud copy.
        let cloud = FakeCloud()
        cloud.storage[TodoStore.storageKey] = try! JSONEncoder().encode([Todo(title: "From other Mac")])
        let store = makeSyncedStore(cloud: cloud)
        XCTAssertEqual(store.items.map(\.title), ["From other Mac"])
    }

    func test_persist_mirrorsToCloud() {
        let cloud = FakeCloud()
        let store = makeSyncedStore(cloud: cloud)
        store.add("Ship v1.1")
        let data = try! XCTUnwrap(cloud.storage[TodoStore.storageKey])
        let decoded = try! JSONDecoder().decode([Todo].self, from: data)
        XCTAssertEqual(decoded.map(\.title), ["Ship v1.1"])
    }

    func test_externalCloudChange_reloadsAndPublishes() {
        let cloud = FakeCloud()
        let store = makeSyncedStore(cloud: cloud)
        XCTAssertTrue(store.items.isEmpty)

        // Another Mac writes to iCloud, then the system fires the notification.
        cloud.storage[TodoStore.storageKey] = try! JSONEncoder().encode([Todo(title: "Remote add")])
        let published = expectation(description: "items republished from cloud")
        let cancellable = store.$items.dropFirst().sink { items in
            if items.map(\.title) == ["Remote add"] { published.fulfill() }
        }
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud
        )
        wait(for: [published], timeout: 1.0)
        cancellable.cancel()
        XCTAssertEqual(store.items.map(\.title), ["Remote add"])
    }
}
