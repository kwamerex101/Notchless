import XCTest
@testable import Notchless

final class HUDPresenterTests: XCTestCase {
    func testTopIsNotchRoute() {
        XCTAssertTrue(HUDPresenter.isNotchRoute(.top))
    }

    func testNonTopPositionsAreFloatingRoute() {
        for position in HUDPosition.allCases where position != .top {
            XCTAssertFalse(HUDPresenter.isNotchRoute(position), "\(position) should not be the notch route")
        }
    }
}
