import XCTest
import SwiftUI
@testable import Notchless

/// Covers three related fixes to `WidgetController`'s screen/frame handling:
///
/// - Bug 2: a widget bricked at 0x0 when `reconcilePanelsForScreenChange`
///   runs against a transiently empty screen list.
/// - Bug 3: a dragged widget's position must survive quit (persisted via
///   `NSWindow.didMoveNotification`, coalesced).
/// - Bug 4: a screen-change rescue must move the panel without overwriting
///   the user's remembered frame.
@MainActor
final class WidgetControllerScreenAndDragTests: XCTestCase {
    private func makeController() -> (WidgetController, UserDefaults) {
        let defaults = UserDefaults(suiteName: "WidgetControllerScreenAndDragTests-\(UUID().uuidString)")!
        let controller = WidgetController(defaults: defaults)
        controller.contentProvider = { _, _ in AnyView(EmptyView()) }
        return (controller, defaults)
    }

    // MARK: - Bug 2: empty screen list must not rescue-to-zero

    func testReconcileWithEmptyScreenListLeavesThePanelUntouched() {
        let (controller, _) = makeController()
        controller.show(.todos)
        guard let panel = controller.existingPanel(for: .todos) else {
            return XCTFail("expected show(.todos) to create a backing panel")
        }
        let frameBefore = panel.frame

        // Simulates NSScreen.screens reporting empty mid display
        // reconfiguration (the actual trigger can't be produced on demand
        // in a test run).
        controller.screenFramesProvider = { [] }
        controller.reconcilePanelsForScreenChange()

        XCTAssertEqual(panel.frame, frameBefore, "an empty screen list must not be treated as every screen having disconnected")
        XCTAssertGreaterThan(panel.frame.width, 0)
        XCTAssertGreaterThan(panel.frame.height, 0)
    }

    // MARK: - Bug 3: a drag must persist the panel's new position

    func testDraggingAPanelPersistsItsNewFrameAfterTheCoalesceWindow() {
        let (controller, defaults) = makeController()
        controller.show(.todos)
        guard let panel = controller.existingPanel(for: .todos) else {
            return XCTFail("expected show(.todos) to create a backing panel")
        }

        let draggedFrame = CGRect(
            x: panel.frame.origin.x + 130,
            y: panel.frame.origin.y - 60,
            width: panel.frame.width,
            height: panel.frame.height
        )
        // performDrag(with:) ultimately moves the window the same way this
        // does — both post NSWindow.didMoveNotification, which is what the
        // fix observes.
        panel.setFrame(draggedFrame, display: true)

        XCTAssertNotEqual(
            WidgetPersistence(defaults: defaults).frame(for: .todos), draggedFrame,
            "the drag must be coalesced, not persisted synchronously"
        )

        let settled = expectation(description: "coalesce window elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(WidgetPersistence(defaults: defaults).frame(for: .todos), draggedFrame)
    }

    // MARK: - Bug 4: a rescue must be ephemeral

    func testScreenChangeRescueMovesThePanelWithoutOverwritingTheRememberedFrame() {
        let (controller, defaults) = makeController()
        controller.show(.todos)
        guard let panel = controller.existingPanel(for: .todos) else {
            return XCTFail("expected show(.todos) to create a backing panel")
        }

        let rememberedFrame = WidgetPersistence(defaults: defaults).frame(for: .todos)
        XCTAssertEqual(rememberedFrame, panel.frame, "show() should have persisted the frame it applied")

        // A screen layout that doesn't overlap the panel's current frame at
        // all, forcing WidgetPlacement to rescue it — standing in for an
        // external display the widget was parked on disconnecting.
        let unrelatedScreen = CGRect(x: 50_000, y: 50_000, width: 800, height: 600)
        controller.screenFramesProvider = { [unrelatedScreen] }
        controller.reconcilePanelsForScreenChange()

        XCTAssertNotEqual(panel.frame, rememberedFrame, "the rescue should actually have moved the panel")

        let settled = expectation(description: "any coalesced persist would have fired by now")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(
            WidgetPersistence(defaults: defaults).frame(for: .todos), rememberedFrame,
            "a rescue is ephemeral — the user's real remembered position must survive it untouched"
        )
    }
}
