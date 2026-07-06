import XCTest
@testable import Notchless

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
}
