import XCTest
@testable import Notchless

final class BrightnessTests: XCTestCase {
    func test_canSetBrightness_symbolAvailable_builtIn_true() {
        XCTAssertTrue(DisplayService.canSetBrightness(symbolAvailable: true, isBuiltIn: true))
    }

    func test_canSetBrightness_symbolUnavailable_builtIn_false() {
        XCTAssertFalse(DisplayService.canSetBrightness(symbolAvailable: false, isBuiltIn: true))
    }

    func test_canSetBrightness_symbolAvailable_external_false() {
        XCTAssertFalse(DisplayService.canSetBrightness(symbolAvailable: true, isBuiltIn: false))
    }

    func test_canSetBrightness_symbolUnavailable_external_false() {
        XCTAssertFalse(DisplayService.canSetBrightness(symbolAvailable: false, isBuiltIn: false))
    }
}
