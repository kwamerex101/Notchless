import XCTest
@testable import Notchless

final class FloatingHUDPositionerTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let hudSize = CGSize(width: 200, height: 60)
    private let inset: CGFloat = 20

    private func origin(_ position: HUDPosition, screenFrame: NSRect? = nil) -> CGPoint {
        FloatingHUDPositioner.frame(
            for: position,
            hudSize: hudSize,
            in: screenFrame ?? self.screenFrame,
            inset: inset
        ).origin
    }

    func testTopLeft() {
        XCTAssertEqual(origin(.topLeft), CGPoint(x: 20, y: 720))
    }

    func testTop() {
        XCTAssertEqual(origin(.top), CGPoint(x: 400, y: 720))
    }

    func testTopRight() {
        XCTAssertEqual(origin(.topRight), CGPoint(x: 780, y: 720))
    }

    func testLeft() {
        XCTAssertEqual(origin(.left), CGPoint(x: 20, y: 370))
    }

    func testCenter() {
        XCTAssertEqual(origin(.center), CGPoint(x: 400, y: 370))
    }

    func testRight() {
        XCTAssertEqual(origin(.right), CGPoint(x: 780, y: 370))
    }

    func testBottomLeft() {
        XCTAssertEqual(origin(.bottomLeft), CGPoint(x: 20, y: 20))
    }

    func testBottom() {
        XCTAssertEqual(origin(.bottom), CGPoint(x: 400, y: 20))
    }

    func testBottomRight() {
        XCTAssertEqual(origin(.bottomRight), CGPoint(x: 780, y: 20))
    }

    func testSizeIsPreserved() {
        let frame = FloatingHUDPositioner.frame(
            for: .center,
            hudSize: hudSize,
            in: screenFrame,
            inset: inset
        )
        XCTAssertEqual(frame.size, hudSize)
    }

    func testNonZeroScreenOriginShiftsTopLeft() {
        let shiftedScreen = NSRect(x: 100, y: 50, width: 1000, height: 800)
        XCTAssertEqual(origin(.topLeft, screenFrame: shiftedScreen), CGPoint(x: 120, y: 770))
    }

    func testNonZeroScreenOriginShiftsCenter() {
        let shiftedScreen = NSRect(x: 100, y: 50, width: 1000, height: 800)
        XCTAssertEqual(origin(.center, screenFrame: shiftedScreen), CGPoint(x: 500, y: 420))
    }
}
