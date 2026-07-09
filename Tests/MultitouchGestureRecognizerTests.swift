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

extension MultitouchGestureRecognizerTests {
    private func touches(_ pts: [(Double, Double)], state: Int = FingerTouch.touching) -> [FingerTouch] {
        pts.enumerated().map { FingerTouch(x: $0.element.0, y: $0.element.1, id: $0.offset, state: state) }
    }

    // Three fingers, centroid (0.35, 0.50).
    private var threeBase: [(Double, Double)] { [(0.30, 0.50), (0.35, 0.50), (0.40, 0.50)] }

    func test_swipeRight_firesOnce_thenLatches() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        XCTAssertNil(r.recognize(touches: touches(threeBase), timestamp: 0.0))   // peak→3, arming
        XCTAssertNil(r.recognize(touches: touches(threeBase), timestamp: 0.06))  // armed, baseline
        let right = threeBase.map { ($0.0 + 0.20, $0.1) }                        // dx=+0.20
        XCTAssertEqual(r.recognize(touches: touches(right), timestamp: 0.10), .swipe(.right))
        let more = threeBase.map { ($0.0 + 0.30, $0.1) }
        XCTAssertNil(r.recognize(touches: touches(more), timestamp: 0.14))       // latched
    }

    func test_swipeLeft() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let left = threeBase.map { ($0.0 - 0.20, $0.1) }
        XCTAssertEqual(r.recognize(touches: touches(left), timestamp: 0.10), .swipe(.left))
    }

    func test_swipeUp_and_down() {
        var up = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = up.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = up.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(up.recognize(touches: touches(threeBase.map { ($0.0, $0.1 + 0.20) }), timestamp: 0.10), .swipe(.up))

        var down = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = down.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = down.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(down.recognize(touches: touches(threeBase.map { ($0.0, $0.1 - 0.20) }), timestamp: 0.10), .swipe(.down))
    }

    // Four fingers around centroid (0.50,0.50), mean radius 0.15.
    private var fourBase: [(Double, Double)] { [(0.35, 0.50), (0.65, 0.50), (0.50, 0.35), (0.50, 0.65)] }

    func test_fourFingerSpread() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.06)   // baseline radius 0.15
        let spread: [(Double, Double)] = [(0.20, 0.50), (0.80, 0.50), (0.50, 0.20), (0.50, 0.80)]  // radius 0.30, dr=+0.15
        XCTAssertEqual(r.recognize(touches: touches(spread), timestamp: 0.10), .spread)
    }

    func test_fourFingerPinch() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.06)
        let pinch: [(Double, Double)] = [(0.47, 0.50), (0.53, 0.50), (0.50, 0.47), (0.50, 0.53)]   // radius 0.03, dr=-0.12
        XCTAssertEqual(r.recognize(touches: touches(pinch), timestamp: 0.10), .pinch)
    }

    func test_settleWindow_landing3then4_firesOnce() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        let three = threeBase
        let four = three + [(0.45, 0.50)]
        XCTAssertNil(r.recognize(touches: touches(three), timestamp: 0.00))  // peak→3, stableSince 0
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.02))   // peak→4, stableSince 0.02
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.06))   // 0.04<0.05, not armed
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.08))   // 0.06>=0.05, armed
        let moved = four.map { ($0.0 + 0.20, $0.1) }
        XCTAssertEqual(r.recognize(touches: touches(moved), timestamp: 0.12), .swipe(.right))
    }

    func test_stateFilter_leavingTouchesNotCounted() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        // 2 touching + 1 leaving (state 7) → count 2 < 3 → nil (no arming).
        let mixed = touches([(0.30, 0.50), (0.35, 0.50)]) + touches([(0.40, 0.50)], state: 7)
        XCTAssertNil(r.recognize(touches: mixed, timestamp: 0.0))
        XCTAssertNil(r.recognize(touches: mixed, timestamp: 0.10))
    }

    func test_twoFingers_neverFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        XCTAssertNil(r.recognize(touches: touches([(0.3, 0.5), (0.5, 0.5)]), timestamp: 0.0))
        XCTAssertNil(r.recognize(touches: touches([(0.6, 0.5), (0.8, 0.5)]), timestamp: 0.1))  // big move, still 2
    }

    func test_subThreshold_noFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let small = threeBase.map { ($0.0 + 0.10, $0.1) }  // dist 0.10 < 0.15
        XCTAssertNil(r.recognize(touches: touches(small), timestamp: 0.10))
    }

    func test_diagonalAmbiguous_noFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let diag = threeBase.map { ($0.0 + 0.13, $0.1 + 0.13) }  // dist 0.184>=0.15, |dx|==|dy| → no dominance
        XCTAssertNil(r.recognize(touches: touches(diag), timestamp: 0.10))
    }

    func test_resetAfterLift_allowsNewGesture() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(r.recognize(touches: touches(threeBase.map { ($0.0 + 0.20, $0.1) }), timestamp: 0.10), .swipe(.right))
        XCTAssertNil(r.recognize(touches: [], timestamp: 0.30))  // fingers lifted → reset
        // New gesture fires again.
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.40)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.46)
        XCTAssertEqual(r.recognize(touches: touches(threeBase.map { ($0.0 - 0.20, $0.1) }), timestamp: 0.50), .swipe(.left))
    }
}
