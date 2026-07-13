import XCTest
@testable import Notchless

final class HUDValueMapperTests: XCTestCase {

    // MARK: - horizontalFraction

    func testHorizontalFractionAtStart() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: 0, width: 200), 0, accuracy: 0.001)
    }

    func testHorizontalFractionAtMidpoint() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: 100, width: 200), 0.5, accuracy: 0.001)
    }

    func testHorizontalFractionAtEnd() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: 200, width: 200), 1, accuracy: 0.001)
    }

    func testHorizontalFractionClampsBelowZero() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: -10, width: 200), 0, accuracy: 0.001)
    }

    func testHorizontalFractionClampsAboveOne() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: 300, width: 200), 1, accuracy: 0.001)
    }

    func testHorizontalFractionZeroWidth() {
        XCTAssertEqual(HUDValueMapper.horizontalFraction(x: 50, width: 0), 0, accuracy: 0.001)
    }

    // MARK: - dialFraction

    func testDialFractionAtTop() {
        let fraction = HUDValueMapper.dialFraction(location: CGPoint(x: 50, y: 0), in: CGSize(width: 100, height: 100))
        // Top wraps to either 0.0 or 1.0 depending on normalization — both are the same dial position.
        XCTAssertTrue(abs(fraction - 0) < 0.001 || abs(fraction - 1) < 0.001,
                       "expected ~0 or ~1, got \(fraction)")
    }

    func testDialFractionAtRight() {
        let fraction = HUDValueMapper.dialFraction(location: CGPoint(x: 100, y: 50), in: CGSize(width: 100, height: 100))
        XCTAssertEqual(fraction, 0.25, accuracy: 0.001)
    }

    func testDialFractionAtBottom() {
        let fraction = HUDValueMapper.dialFraction(location: CGPoint(x: 50, y: 100), in: CGSize(width: 100, height: 100))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    func testDialFractionAtLeft() {
        let fraction = HUDValueMapper.dialFraction(location: CGPoint(x: 0, y: 50), in: CGSize(width: 100, height: 100))
        XCTAssertEqual(fraction, 0.75, accuracy: 0.001)
    }
}
