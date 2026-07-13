import XCTest
@testable import Notchless

final class HUDPresenterTests: XCTestCase {
    func testNotchStyleIsNotchRoute() {
        XCTAssertTrue(HUDPresenter.isNotchRoute(.notch))
    }

    func testNonNotchStylesAreFloatingRoute() {
        for style in HUDStyle.allCases where style != .notch {
            XCTAssertFalse(HUDPresenter.isNotchRoute(style), "\(style) should not be the notch route")
        }
    }
}
