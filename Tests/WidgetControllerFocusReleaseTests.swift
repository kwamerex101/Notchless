import XCTest
import SwiftUI
@testable import Notchless

/// Covers the handoff added to fix the widget focus-stealing defect:
/// `WidgetController.close(_:)` must release a panel's key-focus borrow
/// through the coordinator before ordering it out, otherwise a widget closed
/// while holding the borrow would leave the app activated with no holder
/// left to hand focus back.
@MainActor
final class WidgetControllerFocusReleaseTests: XCTestCase {
    func testCloseReleasesCoordinatorWhileHoldingBorrow() {
        let defaults = UserDefaults(suiteName: "WidgetControllerFocusReleaseTests-\(UUID().uuidString)")!
        let controller = WidgetController(defaults: defaults)
        let coordinator = WidgetFocusCoordinator()
        var deactivateCallCount = 0
        coordinator.activate = {}
        coordinator.deactivate = { deactivateCallCount += 1 }

        controller.focusCoordinator = coordinator
        controller.contentProvider = { _, _ in AnyView(EmptyView()) }
        controller.show(.todos)

        guard let panel = controller.existingPanel(for: .todos) else {
            return XCTFail("expected show(.todos) to create a backing panel")
        }

        coordinator.borrow(panel)
        XCTAssertTrue(panel.wantsKey, "borrowing should flip the panel's wantsKey before it's closed")

        controller.close(.todos)

        XCTAssertFalse(panel.wantsKey, "closing while holding the borrow must release it")
        XCTAssertTrue(coordinator.hasPendingRelease, "release schedules the deactivate on the next runloop turn")

        let expectation = expectation(description: "deactivate runs on the next runloop turn")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(deactivateCallCount, 1, "the app must be handed back once nothing holds the borrow")
    }

    func testCloseWithoutABorrowDoesNotReleaseAnotherPanelsHold() {
        let defaults = UserDefaults(suiteName: "WidgetControllerFocusReleaseTests-\(UUID().uuidString)")!
        let controller = WidgetController(defaults: defaults)
        let coordinator = WidgetFocusCoordinator()
        coordinator.activate = {}
        coordinator.deactivate = {}

        controller.focusCoordinator = coordinator
        controller.contentProvider = { _, _ in AnyView(EmptyView()) }
        controller.show(.todos)
        controller.show(.goals)

        guard let todosPanel = controller.existingPanel(for: .todos),
              let goalsPanel = controller.existingPanel(for: .goals) else {
            return XCTFail("expected both widgets to have backing panels")
        }

        // Goals holds the borrow; Todos never took it.
        coordinator.borrow(goalsPanel)
        XCTAssertFalse(todosPanel.wantsKey)
        XCTAssertTrue(goalsPanel.wantsKey)

        controller.close(.todos)

        XCTAssertTrue(goalsPanel.wantsKey, "closing a widget that never held the borrow must not affect the real holder")
        XCTAssertFalse(coordinator.hasPendingRelease, "no release should be scheduled for a non-holding panel")
    }
}
