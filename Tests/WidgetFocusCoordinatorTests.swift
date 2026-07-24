import XCTest
@testable import Notchless

@MainActor
private final class FakeKeyBorrowingPanel: KeyBorrowingPanel {
    var wantsKey = false
    private(set) var makeKeyCallCount = 0

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyCallCount += 1
    }
}

@MainActor
final class WidgetFocusCoordinatorTests: XCTestCase {
    private var coordinator: WidgetFocusCoordinator!
    private var activateCallCount = 0
    private var deactivateCallCount = 0

    override func setUp() {
        super.setUp()
        coordinator = WidgetFocusCoordinator()
        activateCallCount = 0
        deactivateCallCount = 0
        coordinator.activate = { [weak self] in self?.activateCallCount += 1 }
        coordinator.deactivate = { [weak self] in self?.deactivateCallCount += 1 }
    }

    func testBorrowSetsWantsKeyAndActivates() {
        let panel = FakeKeyBorrowingPanel()
        coordinator.borrow(panel)

        XCTAssertTrue(panel.wantsKey)
        XCTAssertEqual(activateCallCount, 1)
        XCTAssertEqual(panel.makeKeyCallCount, 1)
    }

    func testBorrowingSecondPanelClearsFirstAndDoesNotDeactivate() {
        let first = FakeKeyBorrowingPanel()
        let second = FakeKeyBorrowingPanel()

        coordinator.borrow(first)
        coordinator.borrow(second)

        XCTAssertFalse(first.wantsKey)
        XCTAssertTrue(second.wantsKey)
        XCTAssertEqual(deactivateCallCount, 0, "transferring focus directly must not deactivate")
    }

    func testReleaseSchedulesDeactivate() {
        let panel = FakeKeyBorrowingPanel()
        coordinator.borrow(panel)

        coordinator.release(panel)

        XCTAssertFalse(panel.wantsKey)
        XCTAssertTrue(coordinator.hasPendingRelease)
        XCTAssertEqual(deactivateCallCount, 0, "deactivate must not fire inline")

        let expectation = expectation(description: "deactivate runs on next runloop turn")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(deactivateCallCount, 1)
        XCTAssertFalse(coordinator.hasPendingRelease)
    }

    func testBorrowBeforeScheduledDeactivateRunsCancelsIt() {
        let first = FakeKeyBorrowingPanel()
        let second = FakeKeyBorrowingPanel()

        coordinator.borrow(first)
        coordinator.release(first)
        XCTAssertTrue(coordinator.hasPendingRelease)

        coordinator.borrow(second)
        XCTAssertFalse(coordinator.hasPendingRelease)

        let expectation = expectation(description: "no deactivate fires after cancellation")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(deactivateCallCount, 0)
    }

    func testStaleReleaseFromNonHolderIsIgnored() {
        let first = FakeKeyBorrowingPanel()
        let second = FakeKeyBorrowingPanel()

        coordinator.borrow(first)
        coordinator.borrow(second) // first is no longer the holder

        coordinator.release(first) // stale: first already lost the borrow

        XCTAssertFalse(coordinator.hasPendingRelease)
        XCTAssertTrue(second.wantsKey, "the real holder must be unaffected by the stale release")
        XCTAssertEqual(deactivateCallCount, 0)
    }
}
