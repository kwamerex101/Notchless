import XCTest
@testable import Notchless

final class CircularHUDViewTests: XCTestCase {
    func testTrimEndClampsBelowZero() {
        XCTAssertEqual(CircularHUDView.trimEnd(for: -0.5), 0)
    }

    func testTrimEndClampsAboveOne() {
        XCTAssertEqual(CircularHUDView.trimEnd(for: 1.5), 1)
    }

    func testTrimEndLeavesMidRangeUnchanged() {
        XCTAssertEqual(CircularHUDView.trimEnd(for: 0.42), 0.42)
    }
}
