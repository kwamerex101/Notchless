import XCTest
@testable import Notchless

final class HUDAllDisplaysTests: XCTestCase {
    // MARK: - screenID(containing:in:)

    func testScreenIDContainingPointInSecondFrame() {
        let frames: [(id: CGDirectDisplayID, frame: NSRect)] = [
            (1, NSRect(x: 0, y: 0, width: 1000, height: 800)),
            (2, NSRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let point = CGPoint(x: 1500, y: 400)
        XCTAssertEqual(HUDPresenter.screenID(containing: point, in: frames), 2)
    }

    func testScreenIDContainingPointInFirstFrame() {
        let frames: [(id: CGDirectDisplayID, frame: NSRect)] = [
            (1, NSRect(x: 0, y: 0, width: 1000, height: 800)),
            (2, NSRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let point = CGPoint(x: 500, y: 400)
        XCTAssertEqual(HUDPresenter.screenID(containing: point, in: frames), 1)
    }

    func testScreenIDContainingPointInNeitherFrameReturnsNil() {
        let frames: [(id: CGDirectDisplayID, frame: NSRect)] = [
            (1, NSRect(x: 0, y: 0, width: 1000, height: 800)),
            (2, NSRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let point = CGPoint(x: 2500, y: 400)
        XCTAssertNil(HUDPresenter.screenID(containing: point, in: frames))
    }

    // MARK: - panelsToRemove(existing:current:)

    func testPanelsToRemoveDropsStaleScreens() {
        let existing: Set<CGDirectDisplayID> = [1, 2, 3]
        let current: Set<CGDirectDisplayID> = [2, 3]
        XCTAssertEqual(HUDPresenter.panelsToRemove(existing: existing, current: current), [1])
    }

    func testPanelsToRemoveEmptyWhenUnchanged() {
        let existing: Set<CGDirectDisplayID> = [1, 2, 3]
        let current: Set<CGDirectDisplayID> = [1, 2, 3]
        XCTAssertEqual(HUDPresenter.panelsToRemove(existing: existing, current: current), [])
    }

    func testPanelsToRemoveNeverRemovesStillPresentScreen() {
        let existing: Set<CGDirectDisplayID> = [1]
        let current: Set<CGDirectDisplayID> = [1, 2]
        XCTAssertEqual(HUDPresenter.panelsToRemove(existing: existing, current: current), [])
    }
}
