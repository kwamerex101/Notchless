import XCTest
@testable import Notchless

final class WaveformBufferTests: XCTestCase {
    func test_startsAtFloor() {
        let b = WaveformBuffer(capacity: 4, floor: 0.05)
        XCTAssertEqual(b.samples, [0.05, 0.05, 0.05, 0.05])
    }

    func test_pushLandsOnRightAndScrollsLeft() {
        var b = WaveformBuffer(capacity: 3, floor: 0)
        b.push(0.2); b.push(0.5); b.push(0.9)
        XCTAssertEqual(b.samples, [0.2, 0.5, 0.9])
        b.push(1.0) // 0.2 falls off the left
        XCTAssertEqual(b.samples, [0.5, 0.9, 1.0])
    }

    func test_pushClampsToUnitRange() {
        var b = WaveformBuffer(capacity: 2, floor: 0)
        b.push(-3); b.push(7)
        XCTAssertEqual(b.samples, [0.0, 1.0])
    }

    func test_resetReturnsToFloorNotHalf() {
        var b = WaveformBuffer(capacity: 3, floor: 0.04)
        b.push(0.9); b.push(0.9)
        b.reset()
        XCTAssertEqual(b.samples, [0.04, 0.04, 0.04])
    }
}
