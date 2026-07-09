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
    /// A store backed by an ephemeral suite and no iCloud.
    private func makeStore() -> TodoStore {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        return TodoStore(defaults: suite, cloud: nil)
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

    func test_complete_marksDoneAndKeepsInList() {
        let store = makeStore()
        store.add("A")
        store.complete(store.items[0].id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].isDone)
        XCTAssertEqual(store.completedCount, 1)
        XCTAssertEqual(store.openCount, 0)
    }

    func test_setDone_togglesBothWays() {
        let store = makeStore()
        store.add("A")
        let id = store.items[0].id
        store.setDone(id, true)
        XCTAssertTrue(store.items[0].isDone)
        store.setDone(id, false)
        XCTAssertFalse(store.items[0].isDone)
    }

    func test_clearCompleted_dropsOnlyDoneTasks() {
        let store = makeStore()
        store.add("A"); store.add("B"); store.add("C")
        store.complete(store.items[0].id)   // A done
        store.complete(store.items[2].id)   // C done
        store.clearCompleted()
        XCTAssertEqual(store.items.map(\.title), ["B"])
        XCTAssertEqual(store.completedCount, 0)
    }

    func test_next_skipsDoneTask() {
        let store = makeStore()
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
        let s1 = TodoStore(defaults: suite, cloud: nil)
        s1.add("Persist me")
        let s2 = TodoStore(defaults: suite, cloud: nil)
        XCTAssertEqual(s2.items.map(\.title), ["Persist me"])
    }

    func test_load_recoversFromCorruptData() {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        suite.set(Data("not json".utf8), forKey: TodoStore.storageKey)
        let store = TodoStore(defaults: suite, cloud: nil)
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Two-way iCloud sync

    /// A store wired to a fresh ephemeral suite and the given fake cloud, with
    /// the sync pref forced on so the cloud paths are exercised.
    private func makeSyncedStore(cloud: FakeCloud) -> TodoStore {
        SettingsStore.shared.syncViaICloud = true
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        return TodoStore(defaults: suite, cloud: cloud)
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

    // MARK: - Model: subtasks, notes, migration

    func test_todo_derivedProgressAndFlags() {
        var todo = Todo(title: "Parent")
        XCTAssertEqual(todo.subtaskProgress.total, 0)
        XCTAssertFalse(todo.allSubtasksDone)   // empty is NOT "all done"
        XCTAssertFalse(todo.hasNotes)
        todo.subtasks = [Subtask(title: "a", isDone: true), Subtask(title: "b", isDone: false)]
        todo.notes = "  hello  "
        XCTAssertEqual(todo.subtaskProgress.done, 1)
        XCTAssertEqual(todo.subtaskProgress.total, 2)
        XCTAssertFalse(todo.allSubtasksDone)
        XCTAssertTrue(todo.hasNotes)
        todo.subtasks[1].isDone = true
        XCTAssertTrue(todo.allSubtasksDone)
    }

    func test_todo_hasNotes_isFalseForWhitespaceOnly() {
        var todo = Todo(title: "P")
        todo.notes = "   \n "
        XCTAssertFalse(todo.hasNotes)
    }

    func test_todo_decodesOldJSONWithoutSubtasksOrNotes() throws {
        // v1 JSON: no `subtasks` / `notes` keys; createdAt is the default
        // JSONEncoder Date form (timeIntervalSinceReferenceDate, a number).
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"Legacy\",\"isDone\":false,\"createdAt\":0}"
        let todo = try JSONDecoder().decode(Todo.self, from: Data(json.utf8))
        XCTAssertEqual(todo.id, id)
        XCTAssertEqual(todo.title, "Legacy")
        XCTAssertTrue(todo.subtasks.isEmpty)
        XCTAssertEqual(todo.notes, "")
    }

    func test_todo_roundTripsSubtasksAndNotes() throws {
        var todo = Todo(title: "P", notes: "see https://x.com")
        todo.subtasks = [Subtask(title: "s1", isDone: true)]
        let data = try JSONEncoder().encode(todo)
        let back = try JSONDecoder().decode(Todo.self, from: data)
        XCTAssertEqual(back, todo)
    }

    // MARK: - Store: subtasks & notes

    func test_addSubtask_appendsTrimmedAndRejectsEmpty() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "  step 1  ")
        store.addSubtask(to: pid, title: "   ")
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["step 1"])
    }

    func test_toggleSubtask_flipsAndStays() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.addSubtask(to: pid, title: "b")
        let sid = store.items[0].subtasks[0].id
        store.toggleSubtask(sid, in: pid)
        XCTAssertTrue(store.items[0].subtasks[0].isDone)   // stays in the list
        XCTAssertEqual(store.items[0].subtasks.count, 2)
    }

    func test_toggleLastSubtask_autoCompletesParent() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.addSubtask(to: pid, title: "b")
        store.toggleSubtask(store.items[0].subtasks[0].id, in: pid)
        XCTAssertFalse(store.items[0].isDone)              // not yet: one subtask open
        store.toggleSubtask(store.items[0].subtasks[1].id, in: pid)
        XCTAssertTrue(store.items[0].isDone)               // all done → parent completed, stays
    }

    func test_uncheckSubtask_revertsParentToActive() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        let sid = store.items[0].subtasks[0].id
        store.toggleSubtask(sid, in: pid)                  // all done → parent completes
        XCTAssertTrue(store.items[0].isDone)
        store.toggleSubtask(sid, in: pid)                  // un-check → parent active again
        XCTAssertFalse(store.items[0].isDone)
        XCTAssertEqual(store.items.count, 1)               // never removed
    }

    func test_manualComplete_withOpenSubtasks_keepsParentDone() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.complete(pid)                                // manual override
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].isDone)
    }

    func test_updateSubtaskTitle_removeSubtask_moveSubtask() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        ["a", "b", "c"].forEach { store.addSubtask(to: pid, title: $0) }
        let a = store.items[0].subtasks[0].id
        store.updateSubtaskTitle(a, in: pid, to: "A")
        XCTAssertEqual(store.items[0].subtasks[0].title, "A")
        store.moveSubtask(in: pid, from: IndexSet(integer: 2), to: 0)   // "c" → front
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["c", "A", "b"])
        store.removeSubtask(store.items[0].subtasks[0].id, from: pid)   // removes "c"
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["A", "b"])
    }

    func test_updateNotes_setsNotes() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.updateNotes(of: pid, to: "ping https://x.com")
        XCTAssertEqual(store.items[0].notes, "ping https://x.com")
    }

    func test_completedCount_tracksDoneItems() {
        let store = makeStore()
        store.add("A"); store.add("B"); store.add("C")
        XCTAssertEqual(store.completedCount, 0)
        XCTAssertEqual(store.openCount, 3)
        store.complete(store.items[0].id)
        store.complete(store.items[1].id)
        XCTAssertEqual(store.completedCount, 2)
        XCTAssertEqual(store.openCount, 1)
    }
}
