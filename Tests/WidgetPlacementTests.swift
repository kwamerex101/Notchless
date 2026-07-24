import XCTest
@testable import Notchless

final class WidgetPlacementTests: XCTestCase {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let externalScreen = CGRect(x: 1920, y: -200, width: 1600, height: 1000)
    private let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testFrameFullyOnScreenIsUnchanged() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen, externalScreen], fallback: fallback)
        XCTAssertEqual(result, frame)
    }

    func testFrameOnDisconnectedScreenIsMovedToFallback() {
        // Frame lives entirely within `externalScreen`'s coordinate space,
        // but that screen is no longer in `screens` (disconnected).
        let frame = CGRect(x: 2000, y: 100, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen], fallback: fallback)
        XCTAssertTrue(fallback.contains(result))
        XCTAssertEqual(result.size, frame.size)
    }

    func testFrameMostlyOffScreenButAboveThresholdIsLeftAlone() {
        // 100x50 of the frame remains on `mainScreen` — above the 80x40 floor.
        let frame = CGRect(x: mainScreen.maxX - 100, y: mainScreen.maxY - 50, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen], fallback: fallback)
        XCTAssertEqual(result, frame)
    }

    func testFrameBelowThresholdIsRescued() {
        // Only 50x30 remains visible — below the 80x40 floor.
        let frame = CGRect(x: mainScreen.maxX - 50, y: mainScreen.maxY - 30, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen], fallback: fallback)
        XCTAssertNotEqual(result, frame)
        XCTAssertTrue(fallback.contains(result))
    }

    func testFrameLargerThanFallbackIsShrunkToFit() {
        let hugeFrame = CGRect(x: 5000, y: 5000, width: 2000, height: 1500)
        let result = WidgetPlacement.clamped(frame: hugeFrame, screens: [mainScreen], fallback: fallback)
        XCTAssertLessThanOrEqual(result.width, fallback.width)
        XCTAssertLessThanOrEqual(result.height, fallback.height)
        XCTAssertTrue(fallback.contains(result))
    }

    func testDefaultFrameCentersHorizontallyAndSitsBelowTop() {
        let size = CGSize(width: 300, height: 400)
        let frame = WidgetPlacement.defaultFrame(size: size, on: mainScreen)
        XCTAssertEqual(frame.midX, mainScreen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, mainScreen.maxY - 120, accuracy: 0.001)
        XCTAssertEqual(frame.size, size)
    }

    func testDefaultFrameOnNonZeroOriginExternalScreen() {
        let size = CGSize(width: 300, height: 400)
        let frame = WidgetPlacement.defaultFrame(size: size, on: externalScreen)
        XCTAssertEqual(frame.midX, externalScreen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, externalScreen.maxY - 120, accuracy: 0.001)
        XCTAssertEqual(frame.size, size)
    }

    func testClampedRescueOnNonZeroOriginFallback() {
        let frame = CGRect(x: -5000, y: -5000, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen], fallback: externalScreen)
        XCTAssertTrue(externalScreen.contains(result))
        XCTAssertEqual(result.size, frame.size)
    }

    // MARK: - Bug 2: rescue must never collapse to a zero/undersized frame

    func testRescueAgainstZeroFallbackDoesNotProduceAZeroSizedFrame() {
        // NSScreen.screens can be transiently empty mid display
        // reconfiguration, which leaves WidgetController's fallback at
        // .zero. A rescue against that must not brick the widget behind an
        // invisible 0x0 panel.
        let frame = CGRect(x: 100, y: 100, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [], fallback: .zero)
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
        XCTAssertGreaterThanOrEqual(result.width, WidgetPlacement.minimumSize.width)
        XCTAssertGreaterThanOrEqual(result.height, WidgetPlacement.minimumSize.height)
    }

    func testRescueAgainstUndersizedFallbackYieldsAtLeastTheMinimum() {
        // A fallback screen smaller than the minimum widget size (e.g. a
        // tiny built-in display reported mid-transition) must still rescue
        // to at least minimumSize, even though that overflows the fallback.
        let tinyFallback = CGRect(x: 0, y: 0, width: 100, height: 80)
        let frame = CGRect(x: 5000, y: 5000, width: 300, height: 400)
        let result = WidgetPlacement.clamped(frame: frame, screens: [mainScreen], fallback: tinyFallback)
        XCTAssertGreaterThanOrEqual(result.width, WidgetPlacement.minimumSize.width)
        XCTAssertGreaterThanOrEqual(result.height, WidgetPlacement.minimumSize.height)
    }
}
