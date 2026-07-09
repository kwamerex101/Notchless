import XCTest
@testable import Notchless

final class MultitouchGestureRecognizerTests: XCTestCase {
    func test_gestureTick_equatable() {
        XCTAssertEqual(GestureTick.swipe(.left), .swipe(.left))
        XCTAssertNotEqual(GestureTick.swipe(.left), .swipe(.right))
        XCTAssertNotEqual(GestureTick.pinch, .spread)
    }

    func test_fingerTouch_touchingConstant() {
        XCTAssertEqual(FingerTouch.touching, 4)
    }

    func test_gestureTuning_defaults() {
        let t = GestureTuning()
        XCTAssertEqual(t.gestureMinFingers, 3)
        XCTAssertEqual(t.swipeThreshold, 0.15, accuracy: 0.0001)
    }

    func test_config_gesturesOn_defaultsFalse() {
        // Existing call sites omit gesturesOn; it must default to false.
        let c = TrackpadFeedbackConfig(
            hapticsOn: true, soundOn: true, scrollOn: true, clickOn: true,
            strength: .medium, voiceID: "twig", volume: 0.5)
        XCTAssertFalse(c.gesturesOn)
    }
}
